#!/usr/bin/env bash
# setup-prefix.sh — point a game prefix's ksuser.dll at the installed Proton's
# patched build (stock prefixes ship dead/relative symlinks or files that
# shadow the builtin).
#
# Usage: setup-prefix.sh <prefix-root> <installed-proton>
#   e.g. setup-prefix.sh \
#         ~/.local/share/Steam/steamapps/compatdata/221680/pfx \
#         "~/.local/share/Steam/steamapps/common/Proton - Experimental"
set -euo pipefail

PFX="${1:?usage: setup-prefix.sh <prefix-root> <installed-proton>}"
PROTON="${2:?usage: setup-prefix.sh <prefix-root> <installed-proton>}"

WINE="$PROTON/files/lib/wine"
S32="$PFX/drive_c/windows/system32"
SW64="$PFX/drive_c/windows/syswow64"

[ -d "$S32" ] || { echo "ERROR: prefix not found at $PFX"; exit 1; }
[ -f "$WINE/x86_64-windows/ksuser.dll" ] || { echo "ERROR: patched ksuser.dll not in $WINE (deploy first)"; exit 1; }

# The game loads ksuser.dll explicitly; make sure both WoW64 views resolve to
# the patched build via absolute symlinks.
link() { # link <view-dir> <arch>
    local dir="$1" arch="$2"
    [ -d "$dir" ] || return 0
    mkdir -p "$dir"
    ln -sfn "$WINE/$arch-windows/ksuser.dll" "$dir/ksuser.dll"
    echo "  $dir/ksuser.dll -> $WINE/$arch-windows/ksuser.dll"
}
echo "==> linking ksuser.dll into prefix"
link "$S32" x86_64
link "$SW64" i386

echo "==> done. If the game still doesn't load it, delete the two ksuser.dll paths above"
echo "    so Wine falls back to its builtin (which the patched install provides)."
