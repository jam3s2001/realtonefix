#!/usr/bin/env bash
# deploy-to-proton.sh — copy the patched Wine files into an installed Proton.
#
# Usage: deploy-to-proton.sh <build-dist> <installed-proton>
#   e.g. deploy-to-proton.sh ~/proton-src/build/dist \
#            "~/.local/share/Steam/steamapps/common/Proton - Experimental"
# Backs up the existing files/lib/wine to <installed-proton>/../wine-backup-<date>
# once (does not overwrite an existing backup).
set -euo pipefail

DIST="${1:?usage: deploy-to-proton.sh <build-dist> <installed-proton>}"
PROTON="${2:?usage: deploy-to-proton.sh <build-dist> <installed-proton>}"

WINE_DST="$PROTON/files/lib/wine"
[ -d "$WINE_DST" ] || { echo "ERROR: $WINE_DST not found"; exit 1; }
[ -d "$DIST/files/lib/wine" ] || { echo "ERROR: $DIST/files/lib/wine not found (did the build finish?)"; exit 1; }

BACKUP="$(dirname "$PROTON")/wine-backup-$(date +%Y%m%d)"
if [ ! -d "$BACKUP" ]; then
    echo "==> backing up current wine to $BACKUP"
    cp -a "$WINE_DST" "$BACKUP"
fi

FILES=(
    i386-windows/setupapi.dll    x86_64-windows/setupapi.dll
    i386-windows/ksuser.dll      x86_64-windows/ksuser.dll
    i386-windows/ntdll.dll       x86_64-windows/ntdll.dll
    i386-windows/kernelbase.dll  x86_64-windows/kernelbase.dll
    i386-windows/mmdevapi.dll    x86_64-windows/mmdevapi.dll
    i386-windows/winepulse.drv   x86_64-windows/winepulse.drv
    i386-unix/winepulse.so       x86_64-unix/winepulse.so
    i386-unix/winealsa.so        x86_64-unix/winealsa.so
)

echo "==> deploying patched wine files into $WINE_DST"
for f in "${FILES[@]}"; do
    src="$DIST/files/lib/wine/$f"
    dst="$WINE_DST/$f"
    [ -f "$src" ] || { echo "  MISSING in build: $f — skipping (build older than patch set?)"; continue; }
    [ -f "$dst" ] || { echo "  MISSING in Proton: $f — Proton version mismatch?"; continue; }
    chmod u+w "$dst"
    cp -f "$src" "$dst"
    chmod a-w "$dst"
    echo "  deployed $f"
done

echo "==> done. Remember to run setup-prefix.sh for each game prefix that needs ksuser.dll,"
echo "    and set ForceWDM=0 in Rocksmith.ini."
