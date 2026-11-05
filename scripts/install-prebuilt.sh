#!/usr/bin/env bash
# install-prebuilt.sh — one-command install of RealtoneWine for people who
# just want it to work. No compiling.
#
# What it does:
#   1. finds your Steam + Proton - Experimental install,
#   2. backs up its wine directory (first run only),
#   3. copies the patched DLLs in,
#   4. fixes the Rocksmith game prefix's ksuser.dll link,
#   5. sets ForceWDM=0 in Rocksmith.ini,
#   6. tells you how to launch and verify.
#
# Rollback: everything it touches is backed up; see the summary it prints.
#
# Requirements: Steam with RS2014 (app 221680) and "Proton - Experimental"
# installed, run at least once (so the prefix exists). The prebuilt DLLs were
# built against Proton Experimental 11.0-100 (wine 11.0); other Proton
# versions may work but are untested — use --force if you know better.
set -euo pipefail

FORCE=0
case "${1:-}" in
    --force) FORCE=1 ;;
    "") ;;
    *) echo "usage: $0 [--force]"; exit 2 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREBUILT="$HERE/../prebuilt/files/lib/wine"
[ -d "$PREBUILT" ] || { echo "ERROR: run this from the repo's scripts/ directory (prebuilt/ not found next to it)"; exit 1; }

say() { printf '\n\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*"; }

# 1. find Steam
STEAM="${STEAM_DIR:-$HOME/.local/share/Steam}"
[ -d "$STEAM" ] || STEAM="$HOME/.steam/steam"
[ -d "$STEAM" ] || { echo "ERROR: Steam directory not found (set STEAM_DIR=...)"; exit 1; }
say "Steam found: $STEAM"

# 2. find Proton Experimental
PROTON="$STEAM/steamapps/common/Proton - Experimental"
[ -d "$PROTON/files/lib/wine" ] || { echo "ERROR: 'Proton - Experimental' not installed (install it in Steam, then rerun)"; exit 1; }
say "Proton found: $PROTON"

# version sanity: the prebuilt DLLs are from Proton Experimental 11.0-100.
if [ -f "$PROTON/version" ]; then
    VER=$(cat "$PROTON/version")
    echo "   Proton version file: $VER"
    case "$VER" in
        *11.0-100*) : ;;
        *) warn "prebuilt DLLs were built for Proton Experimental 11.0-100; this is '$VER'."
           [ "$FORCE" = 1 ] || { echo "         rerun with --force to try anyway (rollback is automatic)"; exit 1; } ;;
    esac
fi

# 3. back up wine/ (first run only)
WINE_DST="$PROTON/files/lib/wine"
BACKUP="$(dirname "$PROTON")/wine-backup-realtone-$(date +%Y%m%d-%H%M%S)"
if [ ! -d "$(dirname "$PROTON")"/wine-backup-realtone-* ] 2>/dev/null; then
    say "Backing up current wine -> $(basename "$BACKUP")"
    cp -a "$WINE_DST" "$BACKUP"
else
    say "Backup already exists ($(basename "$(dirname "$PROTON")"/wine-backup-realtone-*)) — keeping the first one"
fi

# 4. install DLLs
say "Installing patched DLLs"
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
for f in "${FILES[@]}"; do
    src="$PREBUILT/$f"; dst="$WINE_DST/$f"
    if [ ! -f "$dst" ]; then warn "target $f not present in this Proton — skipping"; continue; fi
    chmod u+w "$dst"; cp -f "$src" "$dst"; chmod a-w "$dst"
done
say "DLLs installed"

# 5. fix the Rocksmith prefix (app 221680)
APPID=221680
PFX="$STEAM/steamapps/compatdata/$APPID/pfx"
if [ -d "$PFX/drive_c/windows/system32" ]; then
    say "Fixing ksuser.dll links in the Rocksmith prefix"
    ln -sfn "$WINE_DST/x86_64-windows/ksuser.dll" "$PFX/drive_c/windows/system32/ksuser.dll"
    [ -d "$PFX/drive_c/windows/syswow64" ] && \
        ln -sfn "$WINE_DST/i386-windows/ksuser.dll" "$PFX/drive_c/windows/syswow64/ksuser.dll"
else
    warn "Rocksmith prefix not found at $PFX — launch the game once with stock Proton, then rerun this script."
fi

# 6. configure the game
GAME="$STEAM/steamapps/common/Rocksmith2014"
INI="$GAME/Rocksmith.ini"
if [ -f "$INI" ]; then
    cp -n "$INI" "$INI.pre-realtone" 2>/dev/null || true
    say "Setting ForceWDM=0 in Rocksmith.ini"
    if grep -qi "^ForceWDM=" "$INI"; then
        sed -i 's/^\s*ForceWDM\s*=.*/ForceWDM=0/I' "$INI"
    else
        printf '\n[Audio]\nForceWDM=0\n' >> "$INI"
    fi
    grep -qi "^DumpAudioLog=1" "$INI" || sed -i 's/^\s*DumpAudioLog\s*=.*/DumpAudioLog=1/I' "$INI"
else
    warn "Rocksmith.ini not found at $INI — set ForceWDM=0 manually after first launch."
fi

# 7. summary
say "Done. Rollback = copy the backup dir back over files/lib/wine and restore $INI.pre-realtone"
cat <<EOF

Next steps:
  1. (Re)start Steam completely, then launch Rocksmith.
  2. Play! Use the tuner / calibration as normal — the cable should just work.
  3. If anything is off, check Rocksmith2014/audiodump.txt for the line
     '[p:00ff v:12ba] ... INPUT ON Slot N' and include it in your bug report.

NOTE: these DLLs are built against Proton Experimental 11.0-100. If Steam
updates Proton Experimental, rerun this script (the files get replaced by the
update).
EOF
