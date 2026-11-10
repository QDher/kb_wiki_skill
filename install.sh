#!/usr/bin/env bash
# Install a kb-wiki skill as a Claude Code plugin (auto-updated from GitHub) and set up the wiki.
#
# Usage:  curl -fsSL https://raw.githubusercontent.com/QDher/kb_wiki_skill/main/install.sh | bash -s -- [options]
#    or:  bash install.sh [options]
#   (default)       plugin kb-wiki-shell (bash + jq, no Python)
#   --python        plugin kb-wiki (Python 3.8+), e.g. on Nibi
#   --kb-root DIR   wiki folder (default: $KB_ROOT or $HOME/kb)
#   --wiki-repo URL clone an existing wiki repository into the wiki folder instead of creating one
#   --no-wiki       install the plugin only
#   --dry-run       print the actions without changing anything
# Safe to run again: the plugin is updated, existing wiki files are kept, the CLAUDE.md import is added once.
set -euo pipefail

MARKET="kb-wiki-skills"; SOURCE="${KB_WIKI_SOURCE:-QDher/kb_wiki_skill}"   # override for testing (local path)
PLUGIN="kb-wiki-shell"; KB="${KB_ROOT:-$HOME/kb}"; REPO=""; WIKI=1; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --python) PLUGIN="kb-wiki"; shift ;;
    --kb-root) KB="$2"; shift 2 ;;
    --wiki-repo) REPO="$2"; shift 2 ;;
    --no-wiki) WIKI=0; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) echo "see the header of install.sh: https://github.com/$SOURCE/blob/main/install.sh"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

run() { if [ "$DRY" -eq 1 ]; then echo "[dry-run] $*"; else "$@"; fi; }
say() { echo "- $*"; }

command -v claude >/dev/null 2>&1 || { echo "Claude Code (claude) is required: https://code.claude.com" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
if [ "$PLUGIN" = "kb-wiki" ]; then
  command -v python3 >/dev/null 2>&1 || say "warning: python3 not found (on Nibi: module load python)"
else
  command -v jq >/dev/null 2>&1 || say "warning: jq not found; chat digests need it (brew install jq | apt install jq | winget install jqlang.jq)"
fi

# 1. Marketplace and plugin
if claude plugin marketplace list 2>/dev/null | grep -q "> $MARKET\$"; then
  say "updating marketplace $MARKET"
  run claude plugin marketplace update "$MARKET"
else
  say "adding marketplace $SOURCE"
  run claude plugin marketplace add "$SOURCE"
fi
if claude plugin list 2>/dev/null | grep -q "> $PLUGIN@$MARKET\$"; then
  say "updating plugin $PLUGIN"
  run claude plugin update "$PLUGIN@$MARKET"
else
  say "installing plugin $PLUGIN"
  run claude plugin install "$PLUGIN@$MARKET"
fi

# 2. Auto-update: "autoUpdate": true on the marketplace entry in ~/.claude/settings.json
SETTINGS="$HOME/.claude/settings.json"
if [ "$DRY" -eq 1 ]; then
  echo "[dry-run] set extraKnownMarketplaces.$MARKET.autoUpdate = true in $SETTINGS"
elif command -v python3 >/dev/null 2>&1; then
  python3 -I - "$SETTINGS" "$MARKET" <<'PY'
import json, os, sys
path, name = sys.argv[1], sys.argv[2]
data = json.load(open(path)) if os.path.exists(path) else {}
entry = data.setdefault("extraKnownMarketplaces", {}).setdefault(name, {})
entry.setdefault("source", {"source": "github", "repo": "QDher/kb_wiki_skill"})
if entry.get("autoUpdate") is not True:
    entry["autoUpdate"] = True
    tmp = path + ".tmp"
    json.dump(data, open(tmp, "w"), indent=2); open(tmp, "a").write("\n"); os.replace(tmp, path)
PY
  say "auto-update enabled for $MARKET"
elif command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  jq --arg m "$MARKET" '.extraKnownMarketplaces[$m].autoUpdate = true' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  say "auto-update enabled for $MARKET"
else
  say "enable auto-update manually: in Claude Code run /plugin, Marketplaces, $MARKET, Enable auto-update"
fi

# 3. Older copy from previous installers (~/.claude/skills/<name>) would shadow the plugin: move it aside
OLD="$HOME/.claude/skills/$PLUGIN"
if [ -d "$OLD" ]; then
  BAK="$HOME/.claude/$PLUGIN.old-$(date +%Y%m%d%H%M%S)"
  say "moving old copy $OLD to $BAK (delete it when the plugin works)"
  run mv "$OLD" "$BAK"
fi

# 4. Wiki
if [ "$WIKI" -eq 1 ]; then
  if [ -d "$KB/.git" ] || [ -f "$KB/INDEX.md" ]; then
    say "wiki already present at $KB"
  elif [ -n "$REPO" ]; then
    say "cloning $REPO to $KB"
    run git clone "$REPO" "$KB"
  else
    SKILL_DIR="$(ls -td "$HOME/.claude/plugins/cache/$MARKET/$PLUGIN"/*/"$PLUGIN" 2>/dev/null | head -n 1)"
    say "creating wiki at $KB"
    if [ -n "$SKILL_DIR" ]; then run bash "$SKILL_DIR/scripts/init_kb.sh" "$KB"
    else echo "plugin files not found; run again after the install succeeds" >&2; exit 1; fi
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

cat <<MSG

Done. Plugin $PLUGIN@$MARKET updates itself from GitHub; new versions load at the next start of Claude Code.
Add to your shell profile (~/.bashrc or ~/.zshrc):
  export KB_ROOT=$KB
  export SKILL_DIR="\$(ls -td ~/.claude/plugins/cache/$MARKET/$PLUGIN/*/$PLUGIN | head -n 1)"
Restart Claude Code; the skill is listed as /$PLUGIN:$PLUGIN.
MSG
