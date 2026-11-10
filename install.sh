#!/usr/bin/env bash
# Install a kb-wiki skill for Claude Code from this repository and set up the wiki.
#
# Usage: bash install.sh [--python] [--kb-root DIR] [--wiki-repo URL] [--no-wiki] [--dry-run]
#   (default)       install kb-wiki-shell (bash + jq, no Python)
#   --python        install kb-wiki (Python 3.8+) instead, e.g. on Nibi
#   --kb-root DIR   wiki folder (default: $HOME/kb)
#   --wiki-repo URL clone an existing wiki repository into the wiki folder instead of creating one
#   --no-wiki       install the skill only
#   --dry-run       print the actions without changing anything
# Safe to run again: existing files are not overwritten, the CLAUDE.md import is added once.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="kb-wiki-shell"; KB="${KB_ROOT:-$HOME/kb}"; REPO=""; WIKI=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --python) SKILL="kb-wiki"; shift ;;
    --kb-root) KB="$2"; shift 2 ;;
    --wiki-repo) REPO="$2"; shift 2 ;;
    --no-wiki) WIKI=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

run() { if [ "$DRY" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
say() { echo "- $*"; }

[ -f "$SRC/$SKILL/SKILL.md" ] || { echo "missing $SRC/$SKILL/SKILL.md (run from a clone of the repository)" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
if [ "$SKILL" = "kb-wiki" ]; then
  command -v python3 >/dev/null 2>&1 || { echo "python3 is required for --python (on Nibi: module load python)" >&2; exit 1; }
else
  command -v jq >/dev/null 2>&1 || say "warning: jq not found; chat digests need it (brew install jq | apt install jq | winget install jqlang.jq)"
fi

DEST="$HOME/.claude/skills/$SKILL"
run mkdir -p "$HOME/.claude/skills"
if [ -d "$DEST" ]; then
  say "updating $DEST"
  run rm -rf "$DEST"
else
  say "installing $DEST"
fi
run cp -R "$SRC/$SKILL" "$DEST"
if [ "$SKILL" = "kb-wiki" ]; then run chmod +x "$DEST"/scripts/*; else run chmod +x "$DEST"/scripts/*.sh; fi

if [ "$WIKI" -eq 1 ]; then
  if [ -d "$KB/.git" ] || [ -f "$KB/INDEX.md" ]; then
    say "wiki already present at $KB"
  elif [ -n "$REPO" ]; then
    say "cloning $REPO to $KB"
    run git clone "$REPO" "$KB"
  else
    say "creating wiki at $KB"
    run bash "$DEST/scripts/init_kb.sh" "$KB"
  fi
  IMPORT="@$KB/CLAUDE.md"
  CM="$HOME/.claude/CLAUDE.md"
  if [ -f "$CM" ] && grep -Fqx "$IMPORT" "$CM"; then
    say "$CM already imports the wiki rules"
  else
    say "adding $IMPORT to $CM"
    if [ "$DRY" -eq 1 ]; then echo "[dry-run] append $IMPORT to $CM"; else printf '%s\n' "$IMPORT" >> "$CM"; fi
  fi
fi

cat <<EOF

Done. Add these lines to your shell profile (~/.bashrc or ~/.zshrc):
  export KB_ROOT=$KB
  export SKILL_DIR=$DEST
Then restart Claude Code and type /$SKILL to check that the skill is listed.
EOF
