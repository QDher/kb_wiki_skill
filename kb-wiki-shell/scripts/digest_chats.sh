#!/usr/bin/env bash
# Digest chat transcripts into short markdown files. Requires jq 1.6+.
# Usage: digest_chats.sh --out DIR [--min-turns 1] INPUT...
#   INPUT: Claude Code transcripts (~/.claude/projects, *.jsonl) or a claude.ai export conversations.json
# Writes one .md per conversation and chats_index.tsv (one row per conversation, newest first).
set -euo pipefail
. "$(dirname "$0")/lib.sh"
need jq "install: brew install jq | apt install jq | winget install jqlang.jq"
JQ="$(dirname "$0")/digest.jq"

OUT=""; MIN=1; IN=()
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    --min-turns) MIN="$2"; shift 2 ;;
    -h|--help) sed -n '2,5p' "$0"; exit 0 ;;
    *) IN+=("$1"); shift ;;
  esac
done
[ -n "$OUT" ] && [ ${#IN[@]} -gt 0 ] || { sed -n '3p' "$0"; exit 1; }
mkdir -p "$OUT"
ROWS="$(mktemp)"; trap 'rm -f "$ROWS"' EXIT

emit() {  # read JSON lines from stdin, write .md files and index rows
  while IFS= read -r line; do
    name="$(printf '%s' "$line" | jq -r .name)"
    printf '%s' "$line" | jq -r .md > "$OUT/$name"
    printf '%s' "$line" | jq -r '[.name, .kind, .date, .title, .turns, .errors, .chars, .cwd, .source, "", ""] | @tsv' >> "$ROWS"
  done
}

for x in "${IN[@]}"; do
  if [ -d "$x" ]; then find "$x" -type f \( -name '*.jsonl' -o -name conversations.json \); else echo "$x"; fi
done | while IFS= read -r f; do
  case "$f" in
    *.jsonl)
      sess="$(basename "$f" .jsonl)"
      jq -R 'fromjson? // empty' "$f" |
        jq -n -c --arg mode cc --arg src "$f" --arg sess "$sess" --argjson minturns "$MIN" -f "$JQ" | emit ;;
    *.json)
      jq -n -c --arg mode export --arg src "$f" --arg sess "" --argjson minturns "$MIN" -f "$JQ" < "$f" | emit ;;
  esac || echo "skip $f: parse error" >&2
done

{
  printf 'digest\tkind\tdate\ttitle\tturns\terrors\tchars\tcwd\tsource\tdecision\treason\n'
  sort -t "$(printf '\t')" -k3,3r "$ROWS"
} > "$OUT/chats_index.tsv"
echo "$(($(wc -l < "$OUT/chats_index.tsv") - 1)) conversations -> $OUT (index: chats_index.tsv)"
