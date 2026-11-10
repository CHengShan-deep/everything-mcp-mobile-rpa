#!/usr/bin/env bash
#
# Rebuilds a bootstrap archive without documentation, headers and tooling that a
# Python runtime does not need. SYMLINKS.txt is rewritten so the installer never
# recreates a link into a directory that is gone.
#
# Usage: ./scripts/prune-bootstrap.sh <bootstrap.zip>

set -euo pipefail

ZIP="${1:?path to bootstrap zip is required}"
[ -f "$ZIP" ] || { echo "no such archive: $ZIP" >&2; exit 1; }
command -v zip >/dev/null || { echo "'zip' is required" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

unzip -q "$ZIP" -d "$TMP/prefix"
cd "$TMP/prefix"

before=$(du -sm . | cut -f1)

DROP_PATHS=(
	share/doc share/man share/info share/xml share/tor share/swig
	share/fonts share/X11 share/bash-completion share/aclocal
	include
	lib/perl5 lib/tcl8.6 lib/tk8.6 lib/pkgconfig lib/cmake
	libexec/dpkg
	bin/doxygen bin/doxyparse bin/tor bin/swig
)

for p in "${DROP_PATHS[@]}"; do
	rm -rf "$p"
done
python3 - SYMLINKS.txt <<'PY'
import os
import sys

path = sys.argv[1]
if not os.path.exists(path):
    raise SystemExit(0)

kept, dropped = [], 0
for line in open(path, encoding="utf-8").read().splitlines():
    link = line.split("←", 1)[1] if "←" in line else None
    if link is None or os.path.exists(os.path.dirname(link)):
        kept.append(line)
    else:
        dropped += 1

open(path, "w", encoding="utf-8").write("\n".join(kept) + "\n")
print(f"SYMLINKS.txt: kept {len(kept)}, dropped {dropped}")
PY

after=$(du -sm . | cut -f1)
echo "pruned $((before - after)) MB ($before MB -> $after MB uncompressed)"

# zip updates an existing archive in place and keeps entries whose files are
# gone, so the pruned tree has to be written to a fresh archive.
zip -q -r9 "$TMP/bootstrap.zip" ./*
mv -f "$TMP/bootstrap.zip" "$ZIP"
ls -l "$ZIP"
