#!/usr/bin/env bash
#
# Builds a Termux bootstrap archive from source for one architecture, using a
# custom Android package name / prefix.
#
# Required env:
#   ARCH            aarch64 | x86_64
# Optional env:
#   PACKAGE_NAME    Android application id that will own the prefix
#                   (default: com.ynk.virtualdisplay.runtime)
#   TERMUX_REF      termux-packages git ref (default: master)
#   EXTRA_PACKAGES  comma-separated packages added on top of the default
#                   bootstrap set (default: python)
#
# Output: work/termux-packages/bootstrap-<arch>.zip

set -euo pipefail

: "${ARCH:?ARCH is required (aarch64|x86_64)}"
PACKAGE_NAME="${PACKAGE_NAME:-com.ynk.virtualdisplay.runtime}"
TERMUX_REF="${TERMUX_REF:-master}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-python}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/work"
TP="$WORK/termux-packages"

mkdir -p "$WORK"

if [ ! -d "$TP/.git" ]; then
  git clone --depth 1 --branch "$TERMUX_REF" \
    https://github.com/termux/termux-packages.git "$TP"
fi

git -C "$TP" rev-parse HEAD | tee "$WORK/termux-packages.commit"

# properties.sh hardcodes the package name; there is no env override for it,
# and every path below TERMUX_APP__DATA_DIR derives from this one line.
python3 - "$TP/scripts/properties.sh" "$PACKAGE_NAME" <<'PY'
import sys

path, name = sys.argv[1], sys.argv[2]
src = open(path, encoding="utf-8").read()
old = 'TERMUX_APP__PACKAGE_NAME="com.termux"'
if src.count(old) != 1:
    sys.exit(f"expected exactly one {old!r} in {path}, found {src.count(old)}")
open(path, "w", encoding="utf-8").write(
    src.replace(old, f'TERMUX_APP__PACKAGE_NAME="{name}"')
)
print(f"patched {path}: {old} -> TERMUX_APP__PACKAGE_NAME=\"{name}\"")
PY

cd "$TP"
grep -n 'TERMUX_APP__PACKAGE_NAME=' scripts/properties.sh | head -2

export CI=true
./scripts/run-docker.sh ./scripts/build-bootstraps.sh \
  --architectures "$ARCH" \
  --add "$EXTRA_PACKAGES"

ls -l "$TP"/bootstrap-*.zip
