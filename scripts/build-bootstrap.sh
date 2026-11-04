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

# The bootstrap package list still names bzip2, which was renamed to libbz2 in
# master. The official CI builds bootstraps from published debs instead of this
# script, so the list is not kept in sync.
python3 - "$TP/scripts/build-bootstraps.sh" <<'PY'
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
old, new = 'PACKAGES+=("bzip2")', 'PACKAGES+=("libbz2")'
if src.count(old) != 1:
    sys.exit(f"expected exactly one {old!r} in {path}, found {src.count(old)}")
open(path, "w", encoding="utf-8").write(src.replace(old, new))
print(f"patched {path}: bzip2 -> libbz2")
PY

# Two upstream source hosts reset or time out from CI runners while everything
# else downloads fine. Rewrite them to equivalent mirrors serving identical
# bytes, so the pinned checksums still match.
python3 - "$TP/scripts/build/termux_download.sh" <<'PY'
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
anchor = '\tlocal URL="$1"\n'
if src.count(anchor) != 1:
    sys.exit(f"expected exactly one {anchor!r} in {path}, found {src.count(anchor)}")
rewrite = '''\tlocal URL="$1"
\tcase "$URL" in
\t\thttp://download.savannah.gnu.org/*) URL="https://download.savannah.gnu.org/${URL#http://download.savannah.gnu.org/}" ;;
\t\thttps://mirrors.kernel.org/gnu/*) URL="https://ftp.gnu.org/gnu/${URL#https://mirrors.kernel.org/gnu/}" ;;
\tesac
'''
open(path, "w", encoding="utf-8").write(src.replace(anchor, rewrite))
print(f"patched {path}: added mirror rewrites")
PY

export CI=true

# run-docker.sh loads a restrictive AppArmor profile that denies creating files
# in the bind mount, even though the builder uid matches the runner uid, so the
# image is run directly. It still needs the fuse device and mount capability
# that run-docker.sh otherwise supplies: the build assembles the fake prefix
# with fuse-overlayfs.
LOG="$WORK/build-$ARCH.log"
set +e
docker run --rm --init \
  --volume "$TP:/home/builder/termux-packages" \
  --workdir /home/builder/termux-packages \
  --device /dev/fuse \
  --cap-add SYS_ADMIN \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --env CI=true \
  ghcr.io/termux/package-builder \
  ./scripts/build-bootstraps.sh \
  --architectures "$ARCH" \
  --add "$EXTRA_PACKAGES" 2>&1 | tee "$LOG"
rc=${PIPESTATUS[0]}
set -e

if [ "$rc" -ne 0 ]; then
  echo "::error::build-bootstraps.sh exited with $rc for $ARCH"
  echo "----- last 200 lines of $LOG -----"
  tail -n 200 "$LOG"
  exit "$rc"
fi

ls -l "$TP"/bootstrap-*.zip
