#!/usr/bin/env python3
"""Pseudonymise a server inventory dump so that it can live in a PUBLIC repository.

Everything that could identify or grant access to the host is replaced:

  * PEM blocks                -> <REDACTED-PEM:TYPE>
  * the VPN host from secrets -> <vpn-host>
  * public IPv4 / IPv6        -> <ip-N> / <ip6-N>   (stable within a run)
  * hostnames not on the      -> <domain-N>         (stable within a run)
    infrastructure allowlist
  * password/secret/token/... -> <redacted>
    values in key=value pairs
  * high-entropy blobs        -> <redacted-token>
  * e-mail addresses          -> <email>

The mapping itself is never written out - only the counts, so the structure of
the configuration stays readable without leaking what it points at.

Usage: sanitize.py <dump-dir>
"""

import os
import re
import sys

DUMP = sys.argv[1]
VPN_HOST_RAW = os.environ.get("VPN_HOST_RAW", "").strip()

# Hostnames that describe public infrastructure and reveal nothing about the
# server itself - keeping them is what makes the dump readable.
DOMAIN_ALLOW = {
    "github.com", "githubusercontent.com", "raw.githubusercontent.com", "github.io",
    "docker.io", "docker.com", "ghcr.io", "quay.io", "gcr.io", "registry.k8s.io",
    "ubuntu.com", "debian.org", "archive.ubuntu.com", "security.ubuntu.com",
    "letsencrypt.org", "acme-v02.api.letsencrypt.org", "zerossl.com",
    "cloudflare.com", "cloudflare-dns.com", "one.one.one.one",
    "google.com", "googleapis.com", "gstatic.com", "dns.google",
    "npmjs.org", "npmjs.com", "pypi.org", "python.org", "golang.org", "go.dev",
    "sagernet.org", "sing-box.sagernet.org", "hysteria.network", "apernet.io",
    "enfein.github.io", "v2fly.org", "xtls.github.io", "nginx.org",
    "caddyserver.com", "systemd.io", "freedesktop.org", "kernel.org",
    "mozilla.org", "opendns.com", "quad9.net", "adguard.com", "adguard-dns.com",
    "yandex.net", "example.com", "example.org", "localhost", "localdomain",
    "ipify.org", "icanhazip.com", "ifconfig.me", "speedtest.net",
    "bing.com", "apple.com", "microsoft.com", "gravatar.com",
}

IP_ALLOW = {
    "0.0.0.0", "127.0.0.1", "255.255.255.255", "224.0.0.1",
    "1.1.1.1", "1.0.0.1", "8.8.8.8", "8.8.4.4", "9.9.9.9", "149.112.112.112",
    "77.88.8.8", "77.88.8.1", "208.67.222.222", "208.67.220.220",
    "94.140.14.14", "94.140.15.15", "223.5.5.5", "114.114.114.114",
}

RE_PEM = re.compile(r"-----BEGIN ([A-Z0-9 ]+)-----.*?-----END \1-----", re.S)
RE_IPV4 = re.compile(r"(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])")
RE_IPV6 = re.compile(r"(?<![\w:.])(?:[0-9a-fA-F]{1,4}:){3,7}[0-9a-fA-F]{1,4}(?![\w:.])")
RE_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
RE_FQDN = re.compile(
    r"(?<![\w.-])(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,24}(?![\w-])"
)
RE_SECRET_KV = re.compile(
    r"(?i)((?:pass|password|passwd|passphrase|secret|token|auth|apikey|api_key|api-key|"
    r"privatekey|private_key|psk|preshared|obfs|obfs_password|uuid|credential|"
    r"mtu_key|user_password|hashed_password)[\"']?\s*[:=]\s*[\"']?)([^\s\"',}\]]{3,})"
)
RE_TOKEN = re.compile(r"(?<![\w+/=])[A-Za-z0-9+/=]{24,}(?![\w+/=])")

PRIVATE_PREFIXES = ("10.", "127.", "192.168.", "169.254.", "0.", "255.")

domain_map: dict[str, str] = {}
ip_map: dict[str, str] = {}
ip6_map: dict[str, str] = {}


def is_private_v4(ip: str) -> bool:
    parts = ip.split(".")
    if len(parts) != 4:
        return True
    try:
        octets = [int(p) for p in parts]
    except ValueError:
        return True
    if any(o > 255 for o in octets):
        return True  # not an IP at all (version string, etc.)
    if ip.startswith(PRIVATE_PREFIXES):
        return True
    if octets[0] == 172 and 16 <= octets[1] <= 31:
        return True
    if octets[0] >= 224:
        return True
    return False


def map_domain(name: str) -> str:
    low = name.lower().rstrip(".")
    for allowed in DOMAIN_ALLOW:
        if low == allowed or low.endswith("." + allowed):
            return name
    # bare file names such as "config.yaml" are not hosts
    tld = low.rsplit(".", 1)[-1]
    if tld in {
        "yml", "yaml", "json", "conf", "config", "sh", "py", "go", "txt", "md",
        "log", "service", "socket", "timer", "target", "env", "toml", "ini",
        "js", "ts", "html", "css", "sql", "db", "pid", "sock", "lock", "bak",
        "tmpl", "template", "example", "sample", "old", "new", "orig", "d", "cfg",
    }:
        return name
    if low not in domain_map:
        domain_map[low] = f"<domain-{len(domain_map) + 1}>"
    return domain_map[low]


def map_ip(ip: str) -> str:
    if ip in IP_ALLOW or is_private_v4(ip):
        return ip
    if ip not in ip_map:
        ip_map[ip] = f"<ip-{len(ip_map) + 1}>"
    return ip_map[ip]


def map_ip6(ip: str) -> str:
    low = ip.lower()
    if low.startswith(("fe80:", "fd", "fc", "::1", "ff")):
        return ip
    if low not in ip6_map:
        ip6_map[low] = f"<ip6-{len(ip6_map) + 1}>"
    return ip6_map[low]


def host_variants() -> list:
    """Every spelling of the VPN host that could appear in the dump."""
    out = []
    raw = VPN_HOST_RAW
    if not raw:
        return out
    out.append(raw)
    if "@" in raw:
        raw = raw.split("@", 1)[1]
        out.append(raw)
    if ":" in raw and raw.count(":") == 1:
        raw = raw.rsplit(":", 1)[0]
        out.append(raw)
    return [v for v in dict.fromkeys(out) if len(v) > 3]


HOST_VARIANTS = host_variants()


def scrub(text: str) -> str:
    text = RE_PEM.sub(lambda m: f"<REDACTED-PEM:{m.group(1)}>", text)
    for variant in HOST_VARIANTS:
        text = re.sub(re.escape(variant), "<vpn-host>", text, flags=re.I)
    text = RE_SECRET_KV.sub(lambda m: m.group(1) + "<redacted>", text)
    text = RE_EMAIL.sub("<email>", text)
    text = RE_FQDN.sub(lambda m: map_domain(m.group(0)), text)
    text = RE_IPV4.sub(lambda m: map_ip(m.group(0)), text)
    text = RE_IPV6.sub(lambda m: map_ip6(m.group(0)), text)
    text = RE_TOKEN.sub(
        lambda m: "<redacted-token>"
        if any(c.isdigit() for c in m.group(0)) and any(c.isalpha() for c in m.group(0))
        else m.group(0),
        text,
    )
    return text


def scrub_name(name: str) -> str:
    scrubbed = scrub(name)
    return scrubbed.replace("/", "_") if scrubbed != name else name


def main() -> None:
    files_seen = 0
    for root, dirs, files in os.walk(DUMP):
        dirs[:] = [d for d in dirs if d != ".git"]
        for fname in files:
            path = os.path.join(root, fname)
            try:
                with open(path, "r", encoding="utf-8", errors="replace") as fh:
                    original = fh.read()
            except OSError:
                continue
            cleaned = scrub(original)
            try:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(cleaned)
            except OSError:
                continue
            files_seen += 1

    # second pass: paths themselves can carry the host name
    for root, dirs, files in os.walk(DUMP, topdown=False):
        for name in files + dirs:
            new = scrub_name(name)
            if new != name:
                try:
                    os.rename(os.path.join(root, name), os.path.join(root, new))
                except OSError:
                    pass

    with open(os.path.join(DUMP, "SANITISER-REPORT.txt"), "w", encoding="utf-8") as fh:
        fh.write("Sanitiser report (mapping intentionally not included)\n")
        fh.write(f"files processed        : {files_seen}\n")
        fh.write(f"distinct hosts masked  : {len(domain_map)}\n")
        fh.write(f"distinct IPv4 masked   : {len(ip_map)}\n")
        fh.write(f"distinct IPv6 masked   : {len(ip6_map)}\n")
        fh.write(f"vpn host variants used : {len(HOST_VARIANTS)}\n")

    print(
        f"sanitised {files_seen} files; "
        f"masked {len(domain_map)} hosts, {len(ip_map)} IPv4, {len(ip6_map)} IPv6"
    )


if __name__ == "__main__":
    main()
