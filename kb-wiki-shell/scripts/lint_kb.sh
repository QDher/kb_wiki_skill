#!/usr/bin/env bash
# Lint the wiki: frontmatter, sizes, staleness, index consistency, links, duplicate titles, secrets,
# account-specific values, procedures in CLAUDE.md, repeated commands, token estimate.
# Usage: lint_kb.sh KB_ROOT [--stale-days 180]    Exit code 1 if errors.
set -uo pipefail
. "$(dirname "$0")/lib.sh"

ROOT=""; STALE=180
while [ $# -gt 0 ]; do
  case "$1" in
    --stale-days) STALE="$2"; shift 2 ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done
[ -n "$ROOT" ] || { sed -n '3p' "$0"; exit 1; }
cd "$ROOT" || exit 1
ABS="$(pwd -P)"
CUTOFF="$(days_ago "$STALE")"
ERR="$(mktemp)"; WARN="$(mktemp)"; TITLES="$(mktemp)"; CODE="$(mktemp)"; SIZES="$(mktemp)"
trap 'rm -f "$ERR" "$WARN" "$TITLES" "$CODE" "$SIZES"' EXIT
e() { echo "ERROR $*" >> "$ERR"; }
w() { echo "WARN  $*" >> "$WARN"; }
SECRET='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9_-]{20,}|xox[bap]-[A-Za-z0-9-]{10,}|([Pp]assword|[Pp]asswd|[Aa][Pp][Ii][_-]?[Kk]ey|[Tt]oken)[[:space:]]*[:=][[:space:]]*[^[:space:]]{6,}'
# Literal user paths, cluster allocations, Slurm account/partition values (variables and <placeholders> are allowed)
ACCT='(^|[^$A-Za-z0-9_{}])/(home|Users|scratch|project|projects|nearline)/[A-Za-z][A-Za-z0-9._-]*|(^|[^A-Za-z0-9_-])(def|rrg|rpp|ctb)-[a-z][a-z0-9_]*|--(account|partition)[= ][^$<[:space:]]'

PAGES="$(find . \( -name raw -o -name archive -o -name .git -o -name .claude \) -prune -o -type f -name '*.md' -print | sed 's|^\./||' | sort)"
COUNT=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  COUNT=$((COUNT + 1))
  n=$(wc -l < "$rel" | tr -d ' ')
  printf '%s\t%s\n' "$(wc -c < "$rel" | tr -d ' ')" "$rel" >> "$SIZES"
  case "$rel" in CLAUDE.md) [ "$n" -gt 60 ] && e "$rel: $n lines > 60" ;; INDEX.md) [ "$n" -gt 150 ] && e "$rel: $n lines > 150" ;; esac
  grep -Eq "$SECRET" "$rel" && e "$rel: possible secret"
  dir="$(dirname "$rel")"
  grep -oE '\]\([^)#[:space:]]+' "$rel" | sed 's/^](//' | while IFS= read -r t; do
    case "$t" in *:*) continue ;; /*|~*) echo "ERROR $rel: link outside wiki (absolute path) $t" >> "$ERR"; continue ;; esac
    if [ -e "$dir/$t" ]; then
      td="$(cd "$(dirname "$dir/$t")" && pwd -P)"
      case "$td/" in "$ABS"/*) ;; *) echo "ERROR $rel: link outside wiki $t" >> "$ERR" ;; esac
    else
      echo "ERROR $rel: broken link $t" >> "$ERR"
    fi
  done
  if [ "$rel" = CLAUDE.md ] && grep -Eq '^[[:space:]]*```' "$rel"; then
    w "CLAUDE.md: code block; move procedures to workflows/ or a skill"
  fi
  case "$rel" in CLAUDE.md|INDEX.md|README.md|log.md) continue ;; esac
  awk -v f="$rel" '/^[[:space:]]*```/ { c = !c; next }
    c { l = $0; gsub(/^[[:space:]]+/, "", l); gsub(/[[:space:]]+$/, "", l); gsub(/[[:space:]]+/, " ", l)
        if (length(l) >= 40) print l "\t" f }' "$rel" >> "$CODE"
  [ "$n" -gt 300 ] && w "$rel: $n lines > 300, consider splitting"
  if [ "$(head -n 1 "$rel")" != "---" ]; then e "$rel: missing frontmatter"; continue; fi
  fm="$(awk 'NR > 1 && /^---/ { exit } NR > 1 { print }' "$rel")"
  val() { printf '%s\n' "$fm" | awk -v k="$1" -F':' '$1 == k { sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]*#.*$/, ""); print; exit }'; }
  for k in title type status scope tags sources last_verified; do [ -n "$(val "$k")" ] || e "$rel: missing '$k'"; done
  v="$(val type)";   case "$v" in ""|rule|workflow|project|knowledge|reference) ;; *) e "$rel: type='$v' not allowed" ;; esac
  v="$(val status)"; case "$v" in ""|active|deprecated) ;; *) e "$rel: status='$v' not allowed" ;; esac
  v="$(val scope)";  case "$v" in ""|portable|account-specific) ;; *) e "$rel: scope='$v' not allowed" ;; esac
  if [ "$v" = portable ]; then
    hits="$(awk 'NR > 1 && /^---/ && !b { b = 1; next } b { print NR ":" $0 }' "$rel" | grep -E "^[0-9]+:.*($ACCT)" | cut -d: -f1 | head -5 | paste -sd, -)"
    [ -n "$hits" ] && w "$rel: account-specific value on portable page (lines $hits): use \$USER, \$HOME, \$PROJECT, \$SCRATCH or set scope: account-specific"
  fi
  lv="$(val last_verified)"
  if printf '%s' "$lv" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
    [ "$(val status)" = active ] && [ "$lv" \< "$CUTOFF" ] && w "$rel: last_verified $lv older than $STALE days"
  elif [ -n "$lv" ]; then e "$rel: last_verified not YYYY-MM-DD"; fi
  t="$(val title | tr 'A-Z' 'a-z')"; [ -n "$t" ] && printf '%s\t%s\n' "$t" "$rel" >> "$TITLES"
  if [ -f INDEX.md ] && ! grep -Fq "$rel" INDEX.md; then w "not in INDEX.md: $rel"; fi
done <<< "$PAGES"

cut -f1 "$TITLES" | sort | uniq -d | while IFS= read -r t; do
  echo "ERROR duplicate title '$t': $(awk -F'\t' -v t="$t" '$1 == t { printf "%s ", $2 }' "$TITLES")" >> "$ERR"
done
if [ -f INDEX.md ]; then
  grep -oE '^[[:space:]]*[-*]?[[:space:]]*`?[A-Za-z0-9_./-]+\.md`?[[:space:]]*\|' INDEX.md | grep -oE '[A-Za-z0-9_./-]+\.md' |
    while IFS= read -r ref; do [ -e "$ref" ] || echo "ERROR INDEX.md lists missing page: $ref" >> "$ERR"; done
else
  e "INDEX.md missing"
fi

sort -u "$CODE" | awk -F'\t' '{ n[$1]++; p[$1] = p[$1] " " $2 }
  END { for (k in n) if (n[k] > 1) printf "WARN  repeated command on%s: %s\n", p[k], substr(k, 1, 70) }' >> "$WARN"

cat "$ERR" "$WARN"
always=0; for f in CLAUDE.md INDEX.md; do [ -f "$f" ] && always=$((always + $(wc -c < "$f" | tr -d ' '))); done
total=$(awk -F'\t' '{ s += $1 } END { print s + 0 }' "$SIZES")
largest="$(sort -t "$(printf '\t')" -k1,1nr "$SIZES" | head -3 | awk -F'\t' '{ printf "%s%s %d", (NR > 1 ? ", " : ""), $2, $1 / 4 }')"
echo "INFO  tokens (~chars/4): always loaded (CLAUDE.md + INDEX.md) $((always / 4)); all pages $((total / 4)); largest: $largest"
ne=$(wc -l < "$ERR" | tr -d ' '); nw=$(wc -l < "$WARN" | tr -d ' ')
echo "$COUNT files checked: $ne errors, $nw warnings"
[ "$ne" -eq 0 ]
