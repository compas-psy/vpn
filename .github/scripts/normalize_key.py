#!/usr/bin/env python3
"""Repair a private key that survived a copy-paste, and describe what it is.

GitHub secrets routinely arrive with the newlines turned into a literal "\\n",
with CRLF endings, or collapsed onto a single line - all of which OpenSSL
rejects with the unhelpful "error in libcrypto". This rewrites the file into a
canonical PEM and prints a description that contains no key material.

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

match = re.search(r"-----BEGIN ([A-Z0-9 ]+?)-----(.*?)-----END \1-----", raw, re.S)
if not match:
    print("key: no PEM envelope found (not a private key, or truncated)")
    sys.exit(0)

kind = match.group(1)
body = match.group(2)

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
padding = (-len(b64)) % 4
try:
    decoded = base64.b64decode(b64 + "=" * padding, validate=True)
except Exception as exc:  # noqa: BLE001 - the message is the diagnosis
    print(f"key: {kind}, base64 body is corrupt ({exc})")
    sys.exit(1)

wrapped = "\n".join(b64[i : i + 64] for i in range(0, len(b64), 64))
out = [f"-----BEGIN {kind}-----"]
if header_lines:
    out.extend(header_lines)
    out.append("")
out.append(wrapped)
out.append(f"-----END {kind}-----")

with open(path, "w") as fh:
    fh.write("\n".join(out) + "\n")

encrypted = any(h.startswith(("Proc-Type", "DEK-Info")) for h in header_lines)
print(f"key: {kind}, body {len(b64)} b64 chars -> {len(decoded)} bytes, rewritten canonically")
if encrypted:
    print("key: PEM headers say it is passphrase-encrypted - unattended ssh cannot use it")
