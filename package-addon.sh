#!/usr/bin/env bash
# Packages this repo into a distributable zip for PC/Mac WoW clients.
#
# Output: ../BattleGroundEnemiesFixed-v<version>.zip   (sibling of this
#         repo, in the shared addons working dir).
#
# The zip contains a single top-level folder `BattleGroundEnemiesFixed/`
# so users on Windows or Mac can extract it directly into:
#   World of Warcraft\_retail_\Interface\AddOns\
#
# Excludes (dev-only, not part of the addon distribution):
#   .git/, .gitignore, .DS_Store, ._* (AppleDouble), .claude/, .vscode/,
#   .luarc.json, .libraries/, AGENTS.md, CLAUDE.md, DEFERRED.md,
#   NEW_CHANGES.md, IMPROVEMENTS.md, README.md, cspell.json,
#   stylua.toml, deploy-to-wow.sh,
#   package-addon.sh, Modules/PerfHUD.lua + libs/PerfHUD-1.0/ (dev-only perf
#   tooling, never shipped to users). The glue's load line + its SavedVariables
#   are stripped from the staged .toc, and the lib's <Include> is stripped from
#   the staged embeds.xml, so the packaged addon has no dangling references.
#
# Kept:
#   .toc / .xml / .lua, libs/, Modules/, fonts/, bge_logo.tga

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$(cd "$SRC/.." && pwd)"
TOC="$SRC/BattleGroundEnemiesFixed.toc"

# --- Read version from .toc (no bump) -----------------------------------
version=$(awk -F': ' '/^## Version:/ { print $2; exit }' "$TOC" | tr -d '[:space:]')
if [[ -z "$version" ]]; then
  echo "ERROR: no '## Version:' line found in $TOC" >&2
  exit 1
fi

ZIP_NAME="BattleGroundEnemiesFixed-v${version}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"

echo "Packaging BattleGroundEnemiesFixed v${version}"
echo "   from: $SRC"
echo "   to:   $ZIP_PATH"

# --- Stage in a temp dir so the zip has a clean BattleGroundEnemiesFixed/ root ---
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

rsync -a \
  --exclude='.git/' \
  --exclude='.gitignore' \
  --exclude='.DS_Store' \
  --exclude='._*' \
  --exclude='.claude/' \
  --exclude='.vscode/' \
  --exclude='.luarc.json' \
  --exclude='.libraries/' \
  --exclude='AGENTS.md' \
  --exclude='CLAUDE.md' \
  --exclude='DEFERRED.md' \
  --exclude='NEW_CHANGES.md' \
  --exclude='IMPROVEMENTS.md' \
  --exclude='NOTES.md' \
  --exclude='DROPPED.md' \
  --exclude='REPORT.md' \
  --exclude='README.md' \
  --exclude='cspell.json' \
  --exclude='stylua.toml' \
  --exclude='deploy-to-wow.sh' \
  --exclude='package-addon.sh' \
  --exclude='Modules/PerfHUD.lua' \
  --exclude='libs/PerfHUD-1.0/' \
  "$SRC/" "$STAGE/BattleGroundEnemiesFixed/"

# --- Strip the dev-only PerfHUD tooling from the staged copy -------------
# Both Modules/PerfHUD.lua (BGE glue) and libs/PerfHUD-1.0/ (the lib) are
# excluded above — they load only on the dev's own client via deploy-to-wow.sh.
# Remove their references from the STAGED files so the packaged addon has no
# dangling references for end users:
#   .toc       — the glue's load line + the PerfHUD SavedVariables
#   embeds.xml — the lib's <Include> line
# Operates on the staged copies only — the working tree is untouched, so local
# testing still loads PerfHUD.
STAGE_TOC="$STAGE/BattleGroundEnemiesFixed/BattleGroundEnemiesFixed.toc"
sed -i '' \
  -e 's/,[[:space:]]*BattleGroundEnemiesPerfHUDLog//' \
  -e '/^## SavedVariablesPerCharacter:[[:space:]]*BattleGroundEnemiesPerfHUD[[:space:]]*$/d' \
  -e '/PerfHUD\.lua/d' \
  "$STAGE_TOC"
STAGE_EMBEDS="$STAGE/BattleGroundEnemiesFixed/embeds.xml"
sed -i '' \
  -e '/PerfHUD-1\.0/d' \
  "$STAGE_EMBEDS"

# --- Zip it -------------------------------------------------------------
# COPYFILE_DISABLE=1 prevents macOS from injecting AppleDouble (._*) files
# into the archive. -X strips extra file attrs (uid/gid/extended attrs) so
# the archive is portable and reproducible across platforms.
rm -f "$ZIP_PATH"
( cd "$STAGE" && COPYFILE_DISABLE=1 zip -rXq "$ZIP_PATH" "BattleGroundEnemiesFixed" )

echo "Done. Wrote $ZIP_PATH"
