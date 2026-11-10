#!/usr/bin/env bash
# Shared helpers. Works with GNU (Linux, WSL, Git Bash) and BSD (macOS) tools, bash 3.2+.

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# File modification date as YYYY-MM-DD
mdate_of() {
  date -r "$1" +%F 2>/dev/null || stat -c %y "$1" 2>/dev/null | cut -c1-10
}

# Today minus N days as YYYY-MM-DD
days_ago() {
  date -d "-$1 days" +%F 2>/dev/null || date -v-"$1"d +%F
}

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1 ($2)" >&2; return 1; }
}
