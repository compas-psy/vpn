#!/usr/bin/env python3
"""Repair a private key that survived a copy-paste, and describe what it is.

GitHub secrets routinely arrive with the newlines turned into a literal "\\n",
with CRLF endings, collapsed onto a single line, or missing the trailing
-----END----- marker - all of which OpenSSL rejects with the unhelpful
"error in libcrypto". This rewrites the file into a canonical PEM.

When the secret is not a private key at all, it says what it is instead. Every
message here is written for a PUBLIC log: it reports shapes, lengths and PEM
marker lines, never key material.

Usage: normalize_key.py <key-path>
"""

import base64
import re
import sys

path = sys.argv[1]

with open(path, "r", errors="replace") as fh:
    raw = fh.read()

# literal escape sequences -> real newlines
raw = raw.replace("\\r\\n", "\n").replace("\\n", "\n").replace("\\r", "\n")
raw = raw.replace("\r\n", "\n").replace("\r", "\n").strip()

# a secret stored as base64 of the whole key
if "-----BEGIN" not in raw:
    compact = re.sub(r"\s+", "", raw)
    if re.fullmatch(r"[A-Za-z0-9+/=]+", compact or "x"):
        try:
            candidate = base64.b64decode(
                compact + "=" * ((-len(compact)) % 4), validate=True
            ).decode("utf-8", "replace")
            if "-----BEGIN" in candidate:
                raw = candidate.strip()
                print("key: secret was base64-wrapped, unwrapped it")
        except Exception:  # noqa: BLE001 - just a probe
            pass


def emit(kind: str, header_lines: list, b64: str) -> None:
    wrapped = "\n".join(b64[i : i + 64] for i in range(0, len(b64), 64))
    out = [f"-----BEGIN {kind}-----"]
    if header_lines:
        out.extend(header_lines)
        out.append("")
    out.append(wrapped)
    out.append(f"-----END {kind}-----")
    with open(path, "w") as fh:
        fh.write("\n".join(out) + "\n")


def describe(kind: str, b64: str, decoded: bytes) -> None:
    print(f"key: {kind}, body {len(b64)} b64 chars -> {len(decoded)} bytes")
    if decoded.startswith(b"openssh-key-v1\x00"):
        print("key: OpenSSH v1 container recognised")


PEM = re.compile(r"-----BEGIN ([A-Z0-9 ]+?)-----(.*?)-----END \1-----", re.S)
match = PEM.search(raw)

if match:
    kind = match.group(1)
    body = match.group(2)
else:
    # No END marker. If the base64 body is intact the marker is all that is
    # missing, and the key is perfectly usable once it is put back.
    begin = re.search(r"-----BEGIN ([A-Z0-9 ]+?)-----", raw)
    if not begin:
        lines = raw.count("\n") + 1 if raw else 0
        print(f"key: NOT a usable private key - {len(raw)} chars, {lines} lines")
        if raw.startswith(("ssh-rsa", "ssh-ed25519", "ssh-dss", "ecdsa-sha2", "sk-ssh")):
            print(f"key: this is a PUBLIC key ({raw.split(None, 1)[0]}) - "
                  "VPN_SSH_KEY needs the PRIVATE half")
        elif "PuTTY-User-Key-File" in raw:
            print("key: this is a PuTTY .ppk - export it as OpenSSH first")
        elif not raw:
            print("key: the secret is empty")
        else:
            print("key: unrecognised format")
        sys.exit(1)

    for line in raw.splitlines():
        if line.startswith("-----"):
            print(f"key: marker line present -> {line}")

    kind = begin.group(1)
    body = raw[begin.end():]
    body = re.split(r"-----END", body)[0]
    print(f"key: END marker missing for {kind}, rebuilding it")

# Old-style encrypted PEM keeps "Proc-Type"/"DEK-Info" header lines that must
# not be folded into the base64 body.
header_lines = []
body_lines = []
for line in body.strip().splitlines():
    stripped = line.strip()
    if not stripped:
        continue
    if ":" in stripped and not re.fullmatch(r"[A-Za-z0-9+/=]+", stripped):
        header_lines.append(stripped)
    else:
        body_lines.append(stripped)

b64 = re.sub(r"[^A-Za-z0-9+/=]", "", "".join(body_lines))
try:
    decoded = base64.b64decode(b64 + "=" * ((-len(b64)) % 4), validate=True)
except Exception as exc:  # noqa: BLE001 - the message is the diagnosis
    print(f"key: {kind}, base64 body is corrupt ({exc}) - the secret is truncated")
    sys.exit(1)

emit(kind, header_lines, b64)
describe(kind, b64, decoded)
if any(h.startswith(("Proc-Type", "DEK-Info")) for h in header_lines):
    print("key: PEM headers say it is passphrase-encrypted - unattended ssh cannot use it")
