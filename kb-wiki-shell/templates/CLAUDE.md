# Knowledge wiki - rules for Claude

1. Read `INDEX.md` first. Open only the pages the task needs.
2. If the index is not enough: `grep -ril "<term>" . --include=*.md --exclude-dir=raw --exclude-dir=archive`, then read matches.
3. Do not read `raw/` or `archive/` unless asked.
4. Follow pages in `rules/` over general habits.
5. Use workflows in `workflows/` as written; report any step that fails.
6. At the end of a session that produced results or fixes, run the installed kb-wiki skill (kb-wiki or kb-wiki-shell) in `update` mode.
7. No secrets, passwords or tokens in any page. No account-specific paths: use `$USER`, `$HOME`, `$PROJECT`, `$SCRATCH`.
8. Style: objective, short sentences, numbers with units, dates YYYY-MM-DD.
