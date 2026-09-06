#!/usr/bin/env python3
"""Split the stream produced by collect.sh back into a directory tree.

collect.sh concatenates the inventory, prefixing every file with a line
"@@@@@ VPNFILE <relative path> @@@@@", because the host has no tar.

Usage: unpack.py <stream-file> <destination-dir>
"""

import os
import re
import sys

src, dst = sys.argv[1], sys.argv[2]

with open(src, encoding="utf-8", errors="replace") as fh:
    data = fh.read()

parts = re.split(r"^@@@@@ VPNFILE (.+?) @@@@@\n?", data, flags=re.M)

written = 0
skipped = 0
# parts[0] is whatever preceded the first header; then (path, body) pairs
for i in range(1, len(parts) - 1, 2):
    rel = parts[i].strip().lstrip("/")
    body = parts[i + 1]

    target = os.path.normpath(os.path.join(dst, rel))
    if not target.startswith(os.path.abspath(dst) + os.sep) and not target.startswith(
        dst.rstrip(os.sep) + os.sep
    ):
        skipped += 1
        continue

    os.makedirs(os.path.dirname(target), exist_ok=True)
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(body)
    written += 1

print(f"unpacked {written} files" + (f", skipped {skipped} unsafe paths" if skipped else ""))
if written == 0:
    sys.exit(1)
