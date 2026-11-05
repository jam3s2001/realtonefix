#!/usr/bin/env bash
# apply-patches.sh — apply the RealtoneWine patch series to a Proton checkout's
# Wine submodule.
#
# Usage: apply-patches.sh [/path/to/proton]
# (defaults to $PWD). Idempotent: skips patches already applied.
set -euo pipefail

PROTON="${1:-$PWD}"
PATCHDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../patches" && pwd)"

WINE="$PROTON/wine"
[ -d "$WINE" ] || { echo "ERROR: $WINE not found — run from (or point at) a Proton checkout"; exit 1; }
[ -f "$WINE/configure" ] || $PROTON/../configure.sh --container-engine=podman 2>/dev/null || true

echo "==> Wine tree: $WINE"
cd "$WINE"

# The tree must be at the upstream submodule commit; refuse if dirty.
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "WARNING: wine submodule has uncommitted changes."
    git status --short | head -10
    read -rp "Continue anyway? [y/N] " a
    [ "${a,,}" = y ] || exit 1
fi

applied=0
skipped=0
for p in "$PATCHDIR"/*.patch; do
    name=$(basename "$p")
    # idempotency: if the patch's changes are already present, git apply reports
    # an error; test with --check first.
    if git apply --check "$p" 2>/dev/null; then
        git apply "$p"
        echo "    applied  $name"
        applied=$((applied+1))
    elif git apply --check --reverse "$p" 2>/dev/null; then
        echo "    already applied: $name"
        skipped=$((skipped+1))
    else
        echo "ERROR: $name neither applies nor is applied — tree state mismatch." >&2
        echo "       Expected base: upstream wine submodule for your Proton version." >&2
        exit 1
    fi
done

echo "==> Done: $applied applied, $skipped already present."
echo "    Patches are NOT committed; 'git -C $WINE diff' shows the full change,"
echo "    'git -C $WINE checkout -- .' reverts it."
