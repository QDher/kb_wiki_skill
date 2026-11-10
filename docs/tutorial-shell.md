# kb-wiki-shell: tutorial for machines without Python

This file covers the `kb-wiki-shell` skill (bash, standard Unix tools, `jq`). It builds the same wiki as the Python version, with the same layout, templates, and rules. For the Python version on Nibi, see [tutorial-nibi-python.md](tutorial-nibi-python.md).

## Before you start

**Requirements**

- Claude Code installed and working.
- bash 3.2+ with `find`, `awk`, `sed`, `grep`, `sort`: Linux, macOS, WSL, or Git Bash on Windows.
- `jq` 1.6+: `brew install jq`, `apt install jq`, or `winget install jqlang.jq`.
- Optional: `pdftotext` (poppler): `brew install poppler` or `apt install poppler-utils`. Without it, PDFs are read by Claude Code directly.
- `git`.
- The folder `kb-wiki-shell/` from this repository (or the archive `kb-wiki-shell.tar.gz`).

**Differences from the Python version**

| Item | Python (`kb-wiki`) | Shell (`kb-wiki-shell`) |
| --- | --- | --- |
| Command | `/kb-wiki` | `/kb-wiki-shell` |
| Inventory and indexes | `.csv` | `.tsv` (tab-separated) |
| Script arguments | `inventory.py ROOT... --out FILE` | `inventory.sh --out FILE ROOT...` |
| PDFs without a converter | Listed in `failed.txt` | Listed in `pdf_todo.txt` |
| Slurm job | Included | Not included |

The wiki is shared through git. `raw/` is not committed, so each machine keeps its own inventory and triage; only the pages are shared.

## Step 1 — Install the skill

**Shortest routes** (see the repository README for details): as a Claude Code plugin,

```bash
claude plugin marketplace add QDher/kb_wiki_skill
claude plugin install kb-wiki-shell@kb-wiki-skills
```

or with the installer script, which also creates the wiki and adds the `CLAUDE.md` import:

```bash
git clone https://github.com/QDher/kb_wiki_skill.git
bash kb_wiki_skill/install.sh
```

With either route, continue at the check in item 3 below (plugin installs: the command is `/kb-wiki-shell:kb-wiki-shell`). The manual steps follow.

1. Copy the skill folder (from a clone of this repository, or by extracting the archive):

```bash
git clone https://github.com/QDher/kb_wiki_skill.git ~/kb_wiki_skill
mkdir -p ~/.claude/skills
cp -r ~/kb_wiki_skill/kb-wiki-shell ~/.claude/skills/
chmod +x ~/.claude/skills/kb-wiki-shell/scripts/*.sh
```

or, from the archive:

```bash
mkdir -p ~/.claude/skills
tar -xzf kb-wiki-shell.tar.gz -C ~/.claude/skills
chmod +x ~/.claude/skills/kb-wiki-shell/scripts/*.sh
```

2. Set the variables (add to `~/.bashrc`, or `~/.zshrc` on macOS, then reload the shell):

```bash
export KB_ROOT=$HOME/kb
export SKILL_DIR=$HOME/.claude/skills/kb-wiki-shell
```

3. Check the skill: start `claude` and type `/kb-wiki-shell`; it should be listed. If not, check that `~/.claude/skills/kb-wiki-shell/SKILL.md` exists.

4. Check the tools:

```bash
jq --version && bash --version | head -1 && git --version
```

## Step 2 — Create the wiki skeleton

```bash
bash $SKILL_DIR/scripts/init_kb.sh $KB_ROOT
```

This creates the folders, `CLAUDE.md`, `INDEX.md`, `README.md`, `log.md`, a `.gitignore` (excludes `raw/`), and a first git commit. Existing files are not overwritten.

If the wiki already exists on another machine, clone it instead and skip `init_kb.sh`:

```bash
git clone <repo-url> $KB_ROOT
```

Make Claude Code load the wiki rules in every session:

```bash
echo "@$HOME/kb/CLAUDE.md" >> ~/.claude/CLAUDE.md
```

Only the 8-line rules file is loaded. Claude opens `INDEX.md` and individual pages on demand.

## Step 3 — Inventory the sources

The inventory lists candidate files with type, size, date, project, and sha256. It changes nothing. Roots go at the end of the command.

```bash
bash $SKILL_DIR/scripts/inventory.sh --out $KB_ROOT/raw/inventory.tsv --source laptop \
  ~/Documents/projects ~/Downloads
```

Options: `--source LABEL` (default: host name), `--max-mb 50` (skip larger files). Skipped folders: `.git`, `node_modules`, `venv`, `site-packages`, caches.

Read the printed summary: file count, count per type, number of exact duplicates.

| Column | Use |
| --- | --- |
| `type` | markdown, pdf, image, transcript, script, slurm-log, ... |
| `duplicate_of` | Path of the first file with the same sha256 |
| `decision`, `reason` | Empty; filled in Step 6 |

Open the `.tsv` in a spreadsheet application if needed; keep the tab delimiter when saving.

## Step 4 — Digest chat transcripts

A digest keeps, per turn: the user request, commands run, files written, errors with the next working command, and the final answer. Tool output is dropped.

**Claude Code sessions on this machine:**

```bash
bash $SKILL_DIR/scripts/digest_chats.sh --out $KB_ROOT/raw/converted/chats --min-turns 2 ~/.claude/projects
```

**claude.ai chats:** open Settings > Privacy > Export data, unzip the file you receive, then run:

```bash
bash $SKILL_DIR/scripts/digest_chats.sh --out $KB_ROOT/raw/converted/chats /path/to/export/conversations.json
```

**Output**

- One file per conversation: `YYYY-MM-DD_<title>_<id>.md`, with frontmatter (`kind`, `cwd`, `turns`, `errors`, empty `decision`).
- `chats_index.tsv`: one row per conversation, newest first. Sort by `errors` to find failed workflows; by `turns` to find trivial chats.

A line starting with `ERROR` is followed by `next OK:` when a later command succeeded. That pair is the material for a "Known pitfalls" line. Malformed lines in a transcript are skipped.

To include Claude Code sessions run on Nibi, copy them first, then pass the copy as input:

```bash
scp -r <user>@nibi.alliancecan.ca:~/.claude/projects ~/nibi-projects
bash $SKILL_DIR/scripts/digest_chats.sh --out $KB_ROOT/raw/converted/chats ~/nibi-projects
```

## Step 5 — Convert PDFs and images

Converted files go to `raw/converted/docs/`, named `<folder>__<file>.md`, each with a `source:` line.

1. Convert one file first:

```bash
bash $SKILL_DIR/scripts/convert_docs.sh --out $KB_ROOT/raw/converted/docs ~/Documents/projects/projA/report.pdf
```

2. Convert everything listed in the inventory (skips duplicates and rows marked `drop`):

```bash
bash $SKILL_DIR/scripts/convert_docs.sh --inventory $KB_ROOT/raw/inventory.tsv --out $KB_ROOT/raw/converted/docs
```

3. Read the printed summary and the lists written to `raw/converted/docs/`:

| File | Meaning | Action |
| --- | --- | --- |
| `pdf_todo.txt` | `pdftotext` not installed | Install poppler and rerun, or ask Claude Code (below) |
| `scanned_pdfs.txt` | PDF with almost no text layer | Ask Claude Code to read the PDF pages as images and write the markdown |
| `images_todo.txt` | Image stubs (`source<TAB>output`) | Ask Claude Code (below) |
| `failed.txt` | `pdftotext` error with the file name | Check that the file opens; rerun with `--force` |

4. In Claude Code, transcribe images and unconverted PDFs:

> Read each file listed in `$KB_ROOT/raw/converted/docs/images_todo.txt` and `pdf_todo.txt`. In the matching `.md` file, replace the TODO (images) or write the content (PDFs) as markdown. For images: visible text plus a 2–5 line description of the figure.

## Step 6 — Triage

Triage assigns each item one decision: `keep`, `merge`, `archive`, or `drop`, with a one-line reason. Two files are triaged: `raw/inventory.tsv` and `raw/converted/chats/chats_index.tsv`.

1. In Claude Code, run:

> Use the kb-wiki-shell skill, ingest mode, step 4 (triage). Fill the `decision` and `reason` columns of `raw/inventory.tsv` and `raw/converted/chats/chats_index.tsv`. Show me the drops and archives as a list before moving anything.

2. Review the proposed decisions. Edit the `.tsv` directly if you disagree.
3. Approve. Claude moves `drop` files to `raw/_to_delete/`. Nothing is deleted.
4. After a final check, delete: `rm -r $KB_ROOT/raw/_to_delete`.

| Case | Detection | Decision |
| --- | --- | --- |
| Exact duplicate | Same sha256 (`duplicate_of` filled) | Keep newest, drop the rest |
| Same topic | Similar title or content | `merge` into one page; newest tested facts win |
| Outdated | Superseded, retired cluster or module version, ended project | `archive`, name the replacement |
| Irrelevant | Small talk, one-off question, test | `drop` |
| Failed workflow | Digest shows `ERROR` lines or an abandoned approach | Keep the final working version only; failure cause becomes one "Known pitfalls" line |
| Secrets or personal data | Passwords, tokens, keys | Remove from text; never commit |

Your own check: open `chats_index.tsv`, sort by `errors` descending, and read the top digests.

## Step 7 — Write wiki pages and the index

Pages are written from the kept and merged items. Raw text is summarized, not copied.

1. In Claude Code, run one project at a time:

> Use the kb-wiki-shell skill, ingest mode, step 5 (distill). Project: projA. Sources: the items marked `keep` or `merge` for projA in the two TSV files. Write pages using `templates/page.md` into `rules/`, `workflows/`, `projects/projA/` and `knowledge/`. Then update `INDEX.md` and `log.md`.

2. Check each new page:

- One topic per page, 50–300 lines.
- Frontmatter complete: `title`, `type`, `status`, `scope`, `tags`, `sources`, `last_verified`.
- Workflows contain numbered steps with exact commands, expected output, and resources (time, memory).
- No personal absolute paths: `$USER`, `$HOME`, `$PROJECT`, `$SCRATCH` instead; otherwise `scope: account-specific`.
- `last_verified` is set only for content that was tested.

3. Each `INDEX.md` line has the form:

```
workflows/nibi-submit.md | Submit compute steps with sbatch | nibi,slurm | 2026-11-10
```

4. Commit:

```bash
git -C $KB_ROOT add -A && git -C $KB_ROOT commit -m "add projA pages"
```

## Step 8 — Lint

```bash
bash $SKILL_DIR/scripts/lint_kb.sh $KB_ROOT
```

Exit code 1 means at least one error. Fix errors before committing; warnings are advisory. Option: `--stale-days 90` changes the staleness threshold.

| Message | Cause | Fix |
| --- | --- | --- |
| `missing frontmatter` / `missing '<key>'` | Required field absent | Add it from `templates/page.md` |
| `type='x' not allowed` | Invalid value | Use `rule`, `workflow`, `project`, `knowledge`, or `reference` |
| `broken link` | Target file missing | Fix the path or remove the link |
| `duplicate title` | Two pages with one title | Merge the pages or rename |
| `possible secret` | Pattern matching a key or password | Remove it and rotate the credential |
| `CLAUDE.md` or `INDEX.md` over limit | More than 60 or 150 lines | Shorten; move detail into pages |
| `last_verified ... older than N days` (warning) | Active page past the threshold | Retest, then update the date, or deprecate |
| `not in INDEX.md` (warning) | Page not indexed | Add one line to `INDEX.md` |

## Step 9 — Daily use

**Search (before a task).** Claude reads `INDEX.md` and opens only relevant pages. To force it:

> Use the kb-wiki-shell skill, search mode: how do I submit array jobs on Nibi?

Manual equivalent:

```bash
grep -ril "sbatch" $KB_ROOT --include=*.md --exclude-dir=raw --exclude-dir=archive
```

**Update (end of a session that produced results or fixes).** In Claude Code:

> Use the kb-wiki-shell skill, update mode. Record what we did and any command that failed and its fix.

Claude then edits only the affected pages, sets `last_verified` for tested content, adds failed attempts as one "Known pitfalls" line, updates `INDEX.md` and `log.md`, and commits locally. It does not push unless asked.

**Sync between machines:**

```bash
git -C $KB_ROOT pull      # before work
git -C $KB_ROOT push      # after the session
```

**Deprecate a page:** set `status: deprecated`, move it to `archive/`, remove its line from `INDEX.md`, and link its replacement. Run `lint` after each update and at least once a month. Ask Claude to run the skill in `clean` mode once a month or when pages overlap: it proposes merges, removals and rewrites with estimated token savings and edits only after you confirm.

## Step 10 — Use the wiki in the claude.ai web app

The web app cannot reach your computer and has no `git`, so ingest and update are not run there.

1. Create or open a Project in claude.ai.
2. Paste the content of `$KB_ROOT/CLAUDE.md` into the Project instructions.
3. Upload to Project knowledge: `INDEX.md` plus the pages needed for that Project. Upload converted `.md` files only, not PDFs or images.
4. After each wiki update, re-upload the changed files. There is no automatic sync.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `/kb-wiki-shell` not listed | Skill not in `~/.claude/skills/kb-wiki-shell/SKILL.md` | Re-copy the folder; restart `claude` |
| `Permission denied` on a script | Execute bit lost | `chmod +x $SKILL_DIR/scripts/*.sh` |
| `missing tool: jq` | `jq` not installed | Install it (Before you start) |
| `$'\r': command not found` | Windows line endings after extraction | For each script: `tr -d '\r' < f.sh > f.tmp && mv f.tmp f.sh` |
| Digest finds 0 conversations | Wrong path or no `.jsonl` files | `ls ~/.claude/projects/*/*.jsonl` |
| Digest prints `skip ...: parse error` | File is not valid JSON | Check the file; other files continue to be processed |
| PDFs listed in `pdf_todo.txt` | `pdftotext` not installed | Install poppler, or use the Claude Code step in Step 5 |
| Claude reads too many pages | Index lines too vague | Make each `INDEX.md` summary specific; add tags |

Tested on Linux with sample data only. macOS (BSD tools) and bash 3.2 are not tested; the scripts include fallbacks for known differences.
