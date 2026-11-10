# kb-wiki skill: step-by-step tutorial (Python version, Nibi)

This file covers the Python version (`kb-wiki`) for Nibi. For machines without Python, use the shell version: [tutorial-shell.md](tutorial-shell.md).

## Before you start

The kb-wiki skill turns scattered files and chats into a markdown wiki that Claude reads through one index file. It runs inside Claude Code, locally or on Nibi.

**Requirements**

- Claude Code installed and working (on Nibi if you ingest Nibi data).
- Python 3.8+ (standard library only). On Nibi: `module load python`.
- `git`.
- Optional: `pip install pymupdf4llm` for better PDF output; `pdftotext` (poppler) is the fallback.

**Terms**

| Term | Meaning |
| --- | --- |
| `KB_ROOT` | Wiki folder, default `~/kb` |
| `SKILL_DIR` | Skill folder inside the plugin cache (computed in `~/.bashrc`, see Step 1) |
| `raw/` | Originals and converted files; never indexed or loaded |
| Page | One markdown file with frontmatter, in `rules/`, `workflows/`, `projects/`, `knowledge/` or `reference/` |

**Order of work:** install, init, inventory, digest chats, convert documents, triage, write pages, lint. After that, daily use is only `search` and `update`.

## Step 1 — Install the skill

The skill is the Claude Code plugin `kb-wiki`. It updates itself from GitHub.

1. Install the plugin, turn on auto-update and create the wiki (or clone it with `--wiki-repo <url>`):

```bash
module load python
curl -fsSL https://raw.githubusercontent.com/QDher/kb_wiki_skill/main/install.sh | bash -s -- --python
```

2. Set the variables (add to `~/.bashrc`, then `source ~/.bashrc`):

```bash
export KB_ROOT=$HOME/kb
export SKILL_DIR="$(ls -td ~/.claude/plugins/cache/kb-wiki-skills/kb-wiki/*/kb-wiki | head -n 1)"
export PROJECT=def-<pi>     # your Slurm allocation
```

3. Check: start `claude` and type `/kb-wiki`; `/kb-wiki:kb-wiki` should be listed. If not: `claude plugin list` must show `kb-wiki@kb-wiki-skills`, enabled.

Updates need no action: Claude Code fetches new versions during a session; they load at the next start. To update at once: `claude plugin marketplace update kb-wiki-skills && claude plugin update kb-wiki@kb-wiki-skills`, then restart `claude`.

To use it on your own computer, run the installer there without `--python` (shell version) or with it.

The installer already created the wiki; Step 2 is for a manual setup.

## Step 2 — Create the wiki skeleton

```bash
bash $SKILL_DIR/scripts/init_kb.sh $KB_ROOT
```

This creates the folders, `CLAUDE.md`, `INDEX.md`, `README.md`, `log.md`, a `.gitignore` (excludes `raw/`), and a first git commit. Existing files are not overwritten.

If the wiki already exists in a repository, clone it instead and skip `init_kb.sh`:

```bash
git clone <repo-url> $KB_ROOT
```

Result:

```
~/kb/
  CLAUDE.md  INDEX.md  README.md  log.md
  rules/ workflows/ projects/ knowledge/ reference/ archive/
  raw/converted/  raw/_to_delete/
```

Next, make Claude Code load the wiki rules in every session:

```bash
echo "@$HOME/kb/CLAUDE.md" >> ~/.claude/CLAUDE.md
```

The wiki itself is not loaded; only its 8-line rules file is. Claude opens `INDEX.md` and individual pages on demand.

## Step 3 — Inventory the sources

The inventory lists every candidate file with type, size, date, project and sha256. It changes nothing.

1. Copy anything you need from `$SCRATCH` into a permanent folder first; scratch is purged.
2. Run:

```bash
python3 $SKILL_DIR/scripts/inventory.py ~/.claude ~/projects $SCRATCH \
  --out $KB_ROOT/raw/inventory.csv --source nibi
```

3. Read the summary printed at the end: file count, count per type, number of exact duplicates.

Options: `--max-mb 50` (skip larger files), `--all-types` (include unknown extensions). Skipped folders: `.git`, `node_modules`, `venv`, `site-packages`, caches.

Inventory columns:

| Column | Use |
| --- | --- |
| `type` | markdown, pdf, image, transcript, script, slurm-log, ... |
| `duplicate_of` | Path of the first file with the same sha256 |
| `decision`, `reason` | Empty; filled in Step 6 |

For files on your own computer, run the same command there with `--source laptop`. Each machine keeps its own inventory; only the pages are shared through git.

## Step 4 — Digest chat transcripts

A digest keeps, per turn: the user request, commands run, files written, errors with the next working command, and the final answer. Tool output is dropped, so a digest is much smaller than the transcript.

**Claude Code sessions on Nibi:**

```bash
python3 $SKILL_DIR/scripts/digest_chats.py ~/.claude/projects \
  --out $KB_ROOT/raw/converted/chats --min-turns 2
```

**claude.ai chats:** in claude.ai, open Settings > Privacy > Export data. Unzip the file you receive, then run:

```bash
python3 $SKILL_DIR/scripts/digest_chats.py /path/to/export/conversations.json \
  --out $KB_ROOT/raw/converted/chats
```

**Output**

- One file per conversation: `YYYY-MM-DD_<title>_<id>.md`, with frontmatter (`kind`, `cwd`, `turns`, `errors`, empty `decision`).
- `chats_index.csv`: one row per conversation, newest first. Sort by `errors` to find failed workflows; sort by `turns` to find trivial chats.

A line starting with `ERROR` in a digest is followed by `next OK:` when a later command succeeded. That pair is the material for a "Known pitfalls" line.

## Step 5 — Convert PDFs and images

Converted files go to `raw/converted/docs/`, named `<folder>__<file>.md`, each with a `source:` line pointing to the original.

1. Run on a few files first:

```bash
python3 $SKILL_DIR/scripts/convert_docs.py ~/projects/projA/report.pdf --out $KB_ROOT/raw/converted/docs
```

2. Convert everything listed in the inventory (skips duplicates and rows marked `drop`):

```bash
python3 $SKILL_DIR/scripts/convert_docs.py --inventory $KB_ROOT/raw/inventory.csv \
  --out $KB_ROOT/raw/converted/docs
```

3. For more than about 20 PDFs, submit it as a job instead of using the login node:

```bash
sbatch --account=$PROJECT $SKILL_DIR/slurm/kb_convert.sbatch
```

4. Read the printed summary and the lists written to `raw/converted/docs/`:

| File | Meaning | Action |
| --- | --- | --- |
| `scanned_pdfs.txt` | PDF with almost no text layer | Run `ocrmypdf in.pdf out.pdf` if available, then repeat the conversion with `--force` |
| `images_todo.txt` | Image stubs (`source<TAB>output`) | Ask Claude Code, see below |
| `failed.txt` | Conversion errors with the message | Fix the cause (missing converter, corrupt file) and rerun |

5. Transcribe images. In Claude Code:

> Read each image listed in `$KB_ROOT/raw/converted/docs/images_todo.txt`. In the matching `.md` file, replace the TODO with the visible text and a 2–5 line description of the figure. If the image content is needed as a picture, copy it to `reference/assets/` and add the link.

For better PDF output, create a virtual environment once: `python -m venv ~/kb-venv && ~/kb-venv/bin/pip install pymupdf4llm`. The sbatch job uses it automatically when present.

## Step 6 — Triage

Triage assigns each item one decision: `keep`, `merge`, `archive` or `drop`, with a one-line reason. Two files are triaged: `raw/inventory.csv` and `raw/converted/chats/chats_index.csv`.

1. In Claude Code, run:

> Use the kb-wiki skill, ingest mode, step 4 (triage). Fill the `decision` and `reason` columns of `raw/inventory.csv` and `raw/converted/chats/chats_index.csv`. Show me the drops and archives as a list before moving anything.

2. Review the proposed decisions. Edit the CSV directly if you disagree.
3. Approve. Claude moves `drop` files to `raw/_to_delete/`. Nothing is deleted.
4. After a final check, delete: `rm -r $KB_ROOT/raw/_to_delete`.

Decision rules the skill applies:

| Case | Detection | Decision |
| --- | --- | --- |
| Exact duplicate | Same sha256 (`duplicate_of` filled) | Keep newest, drop the rest |
| Same topic | Similar title or content | `merge` into one page; newest tested facts win |
| Outdated | Superseded, retired cluster or module version, ended project | `archive`, name the replacement |
| Irrelevant | Small talk, one-off question, test | `drop` |
| Failed workflow | Digest shows `ERROR` lines or an abandoned approach | Keep the final working version only; failure cause becomes one "Known pitfalls" line |
| Secrets or personal data | Passwords, tokens, keys | Remove from text; never commit |

Your own check: open `chats_index.csv`, sort by `errors` descending, and read the top digests. These are the most likely sources of pitfalls and fixes.

## Step 7 — Write wiki pages and the index

Pages are written from the kept and merged items. Raw text is summarized, not copied.

1. In Claude Code, run one project at a time:

> Use the kb-wiki skill, ingest mode, step 5 (distill). Project: projA. Sources: the items marked `keep` or `merge` for projA in the two CSVs. Write pages using `templates/page.md` into `rules/`, `workflows/`, `projects/projA/` and `knowledge/`. Then update `INDEX.md` and `log.md`.

2. Check each new page against these rules:

- One topic per page, 50–300 lines.
- Frontmatter complete: `title`, `type`, `status`, `scope`, `tags`, `sources`, `last_verified`.
- Workflows contain numbered steps with exact commands, expected output and resources (time, memory).
- No absolute personal paths: `$USER`, `$HOME`, `$PROJECT`, `$SCRATCH` instead; otherwise `scope: account-specific`.
- `last_verified` is set only for content that was tested.

3. Check `INDEX.md`. Each line has the form:

```
workflows/nibi-submit.md | Submit compute steps with sbatch | nibi,slurm | 2026-11-10
```

4. Commit:

```bash
git -C $KB_ROOT add -A && git -C $KB_ROOT commit -m "add projA pages"
```

## Step 8 — Lint

```bash
python3 $SKILL_DIR/scripts/lint_kb.py $KB_ROOT
```

Exit code 1 means at least one error. Fix errors before committing; warnings are advisory.

| Message | Cause | Fix |
| --- | --- | --- |
| `missing frontmatter` / `missing '<key>'` | Required field absent | Add it from `templates/page.md` |
| `type='x' not in [...]` | Invalid value | Use `rule`, `workflow`, `project`, `knowledge` or `reference` |
| `broken link` | Target file missing | Fix the path or remove the link |
| `duplicate title` | Two pages with one title | Merge the pages or rename |
| `possible secret` | Pattern matching a key or password | Remove it and rotate the credential |
| `CLAUDE.md` or `INDEX.md` over limit | More than 60 or 150 lines | Shorten; move detail into pages |
| `last_verified N days ago` (warning) | Active page older than 180 days | Retest, then update the date, or deprecate |
| `not in INDEX.md` (warning) | Page not indexed | Add one line to `INDEX.md` |

Option: `--stale-days 90` changes the staleness threshold.

## Step 9 — Daily use

The wiki is in `~/kb`; Claude Code loads `CLAUDE.md` through `~/.claude/CLAUDE.md` (Step 2).

**Search (before a task).** Claude reads `INDEX.md` and opens only relevant pages. To force it:

> Use the kb-wiki skill, search mode: how do I submit array jobs on Nibi?

Manual equivalent:

```bash
grep -ril "sbatch" $KB_ROOT --include=*.md --exclude-dir=raw --exclude-dir=archive
```

**Update (end of a session that produced results or fixes).** In Claude Code:

> Use the kb-wiki skill, update mode. Record what we did and any command that failed and its fix.

Claude then:

1. Edits only the affected page(s) and sets `last_verified` for tested content.
2. Adds failed attempts as one "Known pitfalls" line on the page, not as a new page.
3. Updates `INDEX.md` if a page was added, renamed or deprecated, and adds one line to `log.md`.
4. Commits locally. It does not push unless asked.

**Sync between accounts or machines:**

```bash
git -C $KB_ROOT pull      # before work
git -C $KB_ROOT push      # after the session
```

**Deprecate a page:** set `status: deprecated`, move it to `archive/`, remove its line from `INDEX.md`, and link its replacement.

Run `lint` (Step 8) after each update, and at least once a month. Ask Claude to run the skill in `clean` mode once a month or when pages overlap: it proposes merges, removals and rewrites with estimated token savings and edits only after you confirm.

## Step 10 — Use the wiki in the claude.ai web app

The web app cannot reach Nibi or your computer and has no `git`, so ingest and update are not run there. It only reads a copy of the wiki.

1. Create or open a Project in claude.ai.
2. Paste the content of `$KB_ROOT/CLAUDE.md` into the Project instructions.
3. Upload to Project knowledge: `INDEX.md`, plus the pages needed for that Project (for example everything under `projects/projA/` and the relevant `workflows/` files). Upload converted `.md` files only, not PDFs or images.
4. After each wiki update on Nibi, re-upload the changed files. There is no automatic sync.

Optional: the skill folder can be uploaded as a zip in Settings > Capabilities (code execution enabled). In that case only `lint` and the conversion scripts on files uploaded to the chat are usable; commands using `~/.claude`, `sbatch` or `git` do not apply.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| `/kb-wiki:kb-wiki` not listed | Plugin not installed or disabled | `claude plugin list`; rerun the installer; restart `claude` |
| `Permission denied` on a script | Execute bit lost | `chmod +x $SKILL_DIR/scripts/*` |
| `python3: command not found` or old version | Module not loaded | `module load python` |
| `no PDF converter` in `failed.txt` | Neither pymupdf4llm nor pdftotext available | Create the venv (Step 5) or `module load poppler` |
| Inventory is very large | Scratch contains many files | Pass narrower roots; use `--max-mb 10` |
| Digest step finds 0 conversations | Wrong path or no `.jsonl` files | Check `ls ~/.claude/projects/*/*.jsonl` |
| Conversion job runs out of time or memory | Too many PDFs for the defaults | Edit `#SBATCH --time` and `--mem` in `kb_convert.sbatch` |
| Lint reports `possible secret` on a false match | Pattern is generic | Reword the line; keep the check enabled |
| `git clone` waits for a password | Private repository over HTTPS | Use a personal access token (see the repository README) |
| Claude reads too many pages | Index lines too vague | Make each `INDEX.md` summary specific; add tags |

Scripts were tested on sample data only. Report a failing case with its command and output, and the script can be adjusted.
