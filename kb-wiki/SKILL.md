---
name: kb-wiki
description: Build and maintain the markdown knowledge wiki (kb/) - inventory sources, convert PDFs, images and chat transcripts to markdown, triage duplicate, outdated or failed material, distill pages, update INDEX.md, lint. Use when asked to create, ingest into, update, search or check the wiki, or at the end of a working session to record results.
---

# kb-wiki

Maintains a git-versioned markdown wiki that Claude reads through `INDEX.md`, loading only the pages a task needs.

## Paths

- `KB_ROOT` = wiki root (default `$HOME/kb`). `raw/` inside it holds originals and is never indexed.
- `SKILL_DIR` = folder containing this file (`~/.claude/skills/kb-wiki` or `<repo>/.claude/skills/kb-wiki`).
- Scripts are Python 3.8+ standard library; `pymupdf4llm` is optional for better PDF output.

## Modes

Pick the mode from the request. Ask only if the request matches none.

### init (new wiki)
1. `bash $SKILL_DIR/scripts/init_kb.sh $KB_ROOT`
2. Edit `$KB_ROOT/README.md` variables section for this account.

### ingest (add sources)
1. Inventory: `python3 $SKILL_DIR/scripts/inventory.py <roots...> --out $KB_ROOT/raw/inventory.csv`
   Typical roots on Nibi: `~/.claude ~/projects ~/scratch`. Copy needed scratch files to `raw/` first (scratch is purged).
2. Digest chats: `python3 $SKILL_DIR/scripts/digest_chats.py <files or dirs> --out $KB_ROOT/raw/converted/chats`
   Accepts Claude Code transcripts (`~/.claude/projects/*/*.jsonl`) and claude.ai export `conversations.json`.
3. Convert documents: `python3 $SKILL_DIR/scripts/convert_docs.py --inventory $KB_ROOT/raw/inventory.csv --out $KB_ROOT/raw/converted/docs`
   More than ~20 PDFs: submit `$SKILL_DIR/slurm/kb_convert.sbatch` instead of running on the login node.
   Images: open each path listed in `images_todo.txt` with the Read tool and replace the TODO in its `.md` with a transcription of text and a 2-5 line description.
4. Triage: add a `decision` column (`keep|merge|archive|drop`) and a `reason` column to the inventory. Rules:
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

### lint (check)
`python3 $SKILL_DIR/scripts/lint_kb.py $KB_ROOT` - fix errors, report warnings to the user.

## Rules

- Never read `raw/` or `archive/` unless the task requires it.
- No account-specific values in pages: use `$USER`, `$HOME`, `$PROJECT`, `$SCRATCH`; otherwise set `scope: account-specific`.
- No PDFs or images in claude.ai Project knowledge; only converted `.md`.
- Nibi: compute-heavy steps go through `sbatch`; login nodes only for editing, git, small scripts.
- Writing style: objective, short sentences, numbers with units, dates as YYYY-MM-DD.
