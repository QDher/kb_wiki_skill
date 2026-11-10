---
name: kb-wiki-shell
description: Build and maintain the markdown knowledge wiki (kb/) without Python, using bash, standard Unix tools and jq - inventory sources, convert PDFs, images and chat transcripts to markdown, triage duplicate, outdated or failed material, distill pages, update INDEX.md, lint, audit and de-duplicate existing pages (clean). Use when asked to create, ingest into, update, search, check or clean up the wiki, or at the end of a working session to record results.
---

# kb-wiki-shell

Same wiki and workflow as the Python `kb-wiki` skill (used on Nibi); this version needs no Python.

## Requirements

- bash 3.2+ with standard tools (`find`, `awk`, `sed`, `grep`, `sort`): Linux, macOS, WSL or Git Bash on Windows.
- `jq` 1.6+ for chat digests (`brew install jq`, `apt install jq`, `winget install jqlang.jq`).
- Optional: `pdftotext` (poppler: `brew install poppler`, `apt install poppler-utils`). Without it, PDFs are listed in `pdf_todo.txt` and read by Claude Code directly.
- `git`.

## Paths

- `KB_ROOT` = wiki root (default `$HOME/kb`). `raw/` inside it holds originals and is never indexed.
- `SKILL_DIR` = folder containing this file (the "Base directory for this skill" shown when the skill loads). Installed as a plugin: `~/.claude/plugins/cache/kb-wiki-skills/kb-wiki-shell/<version>/kb-wiki-shell`.
- Inventory and indexes are TSV files (tab-separated); they open in any spreadsheet app.

## Modes

Pick the mode from the request. Ask only if the request matches none.

### init (new wiki)
1. `bash $SKILL_DIR/scripts/init_kb.sh $KB_ROOT`
2. Edit `$KB_ROOT/README.md` variables section for this account.
If the wiki already exists (cloned from git), skip init.

### ingest (add sources)
1. Inventory: `bash $SKILL_DIR/scripts/inventory.sh --out $KB_ROOT/raw/inventory.tsv --source laptop <roots...>`
2. Digest chats: `bash $SKILL_DIR/scripts/digest_chats.sh --out $KB_ROOT/raw/converted/chats <files or dirs>`
   Accepts Claude Code transcripts (`~/.claude/projects/*/*.jsonl`) and claude.ai export `conversations.json`.
3. Convert documents: `bash $SKILL_DIR/scripts/convert_docs.sh --inventory $KB_ROOT/raw/inventory.tsv --out $KB_ROOT/raw/converted/docs`
   Images: open each path in `images_todo.txt` with the Read tool and replace the TODO in its `.md` with a transcription of text and a 2-5 line description.
   PDFs in `pdf_todo.txt` (no pdftotext): read each with the Read tool and write its content as markdown to the listed output path.
4. Triage: fill the `decision` (`keep|merge|archive|drop`) and `reason` columns of `inventory.tsv` and `chats_index.tsv`. Rules:
   - exact duplicate (same sha256, shown in `duplicate_of`): keep newest, drop others
   - near duplicate / same topic: merge into one page, newest tested facts win
   - outdated (superseded, retired clusters, old module versions, ended projects): archive, note replacement
   - irrelevant (small talk, one-off questions, tests): drop
   - failed workflow (error-retry loops, abandoned approach): keep only the final working version; one line per failure cause under "Known pitfalls"; archive the rest
   - secrets or personal data: remove, never commit
   Move drops to `raw/_to_delete/`. Do not delete; the user reviews.
5. Distill: write pages from `$SKILL_DIR/templates/page.md` into `rules/ workflows/ projects/<name>/ knowledge/ reference/`. One topic per page, 50-300 lines, link instead of duplicating. Workflows: numbered steps, exact commands, expected output, resources.
6. Index: one line per page in `INDEX.md`: `path | summary | tags | last_verified`. Add one line to `log.md` (newest first).
7. Run lint (below) and fix errors.

### update (end of session)
1. Update the affected page(s) only; set `last_verified` to today if the content was tested.
2. A failed attempt becomes one "Known pitfalls" line on the page, not a new page.
3. Update `INDEX.md` if a page was added, renamed or deprecated; add one `log.md` line.
4. `git -C $KB_ROOT add -A && git -C $KB_ROOT commit -m "<summary>"` (do not push unless asked).

### search (answer from the wiki)
1. Read `INDEX.md`. 2. `grep -ril "<term>" $KB_ROOT --include=*.md --exclude-dir=raw --exclude-dir=archive` if the index is not enough. 3. Read only matching pages.

### clean (audit existing pages)
Run when the wiki grows, when pages contradict each other, or once a month. No edits before the user confirms.
1. Baseline: `bash $SKILL_DIR/scripts/lint_kb.sh $KB_ROOT`. Note errors, warnings and the `INFO tokens` line.
2. Read `INDEX.md`, then pages one directory or tag at a time (not all at once). Find:
   - repeated commands or setups (lint `repeated command` warnings, same steps on several pages)
   - contradictions between pages, and between `rules/` and `CLAUDE.md`
   - narrative text, introductions, filler: candidates for short imperative bullets or numbered steps
   - procedures in `CLAUDE.md` (lint `code block` warning): move to `workflows/` or a skill, keep a one-line pointer
   - account-specific values on portable pages (lint warning): replace with `$USER`, `$HOME`, `$PROJECT`, `$SCRATCH`, or set `scope: account-specific`
   - stale pages (`last_verified` warnings), deprecated pages still in `INDEX.md`, pages under 10 lines that belong on another page
3. Propose, do not edit: one table `file | issue | proposed change | est. tokens saved` (tokens ~ characters / 4), then the diffs of the main changes. Merges keep one page as the single source; the other pages link to it.
4. Wait for explicit confirmation. Apply only the confirmed items:
   - merged or removed page: set `status: deprecated`, move to `archive/`, update links and `INDEX.md`
   - keep facts and "Known pitfalls" lines; only wording, duplication and placement change
5. Lint again; report tokens before/after (always loaded and total), changes applied, items left open.
6. One `log.md` line; `git -C $KB_ROOT add -A && git -C $KB_ROOT commit -m "clean: <summary>"` (do not push unless asked).

### lint (check)
`bash $SKILL_DIR/scripts/lint_kb.sh $KB_ROOT` - fix errors, report warnings to the user.
Checks: frontmatter, sizes (CLAUDE.md 60, INDEX.md 150, pages 300 lines), staleness, index consistency, broken links and links leaving the wiki, duplicate titles, secrets, account-specific values on `scope: portable` pages, code blocks in CLAUDE.md, commands repeated on several pages. Last lines: `INFO tokens` (always loaded and total) and the error/warning count.

## Rules

- Never read `raw/` or `archive/` unless the task requires it.
- `clean` mode edits only after the user confirms the proposal.
- Links stay inside the wiki: relative paths `[text](path/page.md)`, no absolute paths.
- No account-specific values in pages: use `$USER`, `$HOME`, `$PROJECT`, `$SCRATCH`; otherwise set `scope: account-specific`.
- No PDFs or images in claude.ai Project knowledge; only converted `.md`.
- Commands for Nibi in workflow pages are documented, not run, on this machine.
- Writing style: objective, short sentences, numbers with units, dates as YYYY-MM-DD.
