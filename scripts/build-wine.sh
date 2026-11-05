#!/usr/bin/env bash
# build-wine.sh — build the patched Wine via Proton's build system (podman).
#
# Usage: build-wine.sh [/path/to/proton] [-j N]
# Artifacts: <proton>/build/dist/files/lib/wine/
set -euo pipefail

PROTON="${1:-$PWD}"
JOBS="${2:-$(nproc)}"

[ -d "$PROTON/wine" ] || { echo "ERROR: $PROTON is not a Proton checkout"; exit 1; }

CCACHE_DIR="${CCACHE_DIR:-$HOME/.cache/proton-ccache}"
mkdir -p "$CCACHE_DIR"

cd "$PROTON/build" 2>/dev/null || { mkdir -p "$PROTON/build"; cd "$PROTON/build"; }

if [ ! -f Makefile ]; then
    echo "==> configuring (first time; pulls the SteamRT SDK image)"
    if command -v podman >/dev/null; then ENGINE="--container-engine=podman"; else ENGINE="--container-engine=docker"; fi
    # SELinux (Fedora/Bazzite): label the trees the container can read them.
    if command -v chcon >/dev/null && getenforce 2>/dev/null | grep -qi enforcing; then
        chcon -R -t container_file_t "$PROTON" "$CCACHE_DIR" 2>/dev/null || true
    fi
    CCACHE_DIR="$CCACHE_DIR" ../configure.sh $ENGINE --enable-ccache
fi

echo "==> building wine (-j$JOBS; first build is long, then incremental)"
# NOTE: Proton's `make wine` is a no-op after the first build unless the
# stamp files are removed. The project's docs call this out too.
rm -f .wine-i386-build .wine-x86_64-build .wine-i386-dist .wine-x86_64-dist
rmdir wine 2>/dev/null || true

CCACHE_DIR="$CCACHE_DIR" make wine -j"$JOBS"

echo "==> artifacts in $PROTON/build/dist/files/lib/wine/"
ls "$PROTON/build/dist/files/lib/wine/" 2>/dev/null
