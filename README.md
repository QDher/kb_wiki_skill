# kb_wiki_skill

Claude Code skills that build and maintain a markdown knowledge wiki: inventory sources, convert PDFs, images and chat transcripts to markdown, triage duplicate/outdated/failed material, distill pages, index, lint, audit and de-duplicate existing pages. Claude reads the wiki through a short `INDEX.md` and opens only the pages a task needs.

| Folder | Skill | Runtime | Use on |
| --- | --- | --- | --- |
| `kb-wiki/` | `/kb-wiki` | Python 3.8+ (standard library) | Nibi |
| `kb-wiki-shell/` | `/kb-wiki-shell` | bash, standard Unix tools, `jq`; `pdftotext` optional | Linux, macOS, WSL, Git Bash |

Both produce the same wiki layout and use the same page template. Inventories and indexes are `.csv` (Python) or `.tsv` (shell).

## Install

Pick one route. Routes 1 and 2 install the shell version (`kb-wiki-shell`); route 3 covers the Claude app.

### 1. Claude Code plugin (two commands, no clone)

Run in your terminal:

```bash
claude plugin marketplace add QDher/kb_wiki_skill
claude plugin install kb-wiki-shell@kb-wiki-skills
```

Or, inside a Claude Code session: `/plugin marketplace add QDher/kb_wiki_skill`, then `/plugin install kb-wiki-shell@kb-wiki-skills`. For a private repository, git must be able to authenticate to GitHub (`gh auth login`, an SSH key, or a credential helper). Update later with `claude plugin update kb-wiki-shell@kb-wiki-skills`.

The plugin installs the skill only. Create the wiki afterwards, or ask Claude Code: "use the kb-wiki-shell skill, init mode".

### 2. Installer script (skill and wiki in one step)

```bash
git clone https://github.com/QDher/kb_wiki_skill.git
bash kb_wiki_skill/install.sh                      # shell version, creates ~/kb
bash kb_wiki_skill/install.sh --python             # Python version (Nibi), creates ~/kb
bash kb_wiki_skill/install.sh --wiki-repo https://github.com/<owner>/<wiki-repo>.git   # clone an existing wiki
bash kb_wiki_skill/install.sh --dry-run            # show the actions only
```

The script copies the skill to `~/.claude/skills/`, creates or clones the wiki, adds `@<wiki>/CLAUDE.md` to `~/.claude/CLAUDE.md` (once), and prints the two `export` lines to add to your shell profile. It is safe to run again.

### 3. Claude app (claude.ai and desktop)

The Claude app cannot install a skill from a repository. Upload it once:

```bash
zip -r kb-wiki-shell.zip kb-wiki-shell
```

Then, in the app, open Settings > Capabilities > Skills (the menu name may vary), upload `kb-wiki-shell.zip`, and enable it. Code execution must be on. In the app the skill runs in a cloud sandbox with no access to your computer or Nibi: use it for `lint` and for conversion or digests of files uploaded to the chat. Ingest, update, and git work stay in Claude Code.

### Manual copy

```bash
mkdir -p ~/.claude/skills
cp -r kb_wiki_skill/kb-wiki-shell ~/.claude/skills/      # or kb-wiki
chmod +x ~/.claude/skills/kb-wiki-shell/scripts/*.sh     # or kb-wiki/scripts/*
export KB_ROOT=$HOME/kb
export SKILL_DIR=$HOME/.claude/skills/kb-wiki-shell      # or kb-wiki
bash $SKILL_DIR/scripts/init_kb.sh $KB_ROOT
echo "@$KB_ROOT/CLAUDE.md" >> ~/.claude/CLAUDE.md
```

In Claude Code, run `/kb-wiki` or `/kb-wiki-shell` (installed as a plugin: `/kb-wiki-shell:kb-wiki-shell`). Each `SKILL.md` describes the modes: `init`, `ingest`, `update`, `search`, `clean`, `lint`.

The Python version (`kb-wiki`) is not part of the plugin; use route 2 with `--python` or the manual copy.

## Layout of a wiki

```
kb/  CLAUDE.md  INDEX.md  README.md  log.md
     rules/ workflows/ projects/ knowledge/ reference/ archive/
     raw/   (originals and converted files; not committed, not loaded)
```

## Documentation

- [docs/tutorial-nibi-python.md](docs/tutorial-nibi-python.md): step-by-step tutorial for the Python version on Nibi.
- [docs/tutorial-shell.md](docs/tutorial-shell.md): step-by-step tutorial for the shell version.

## Cloning a private repository over HTTPS

Enter a GitHub personal access token (read access) without storing it in the shell history or in `.git/config`:

```bash
read -rsp "GitHub token: " GHT; echo; export GHT
H='!f() { echo "username=<github-user>"; echo "password=$GHT"; }; f'
git -c credential.helper="$H" clone https://github.com/<owner>/<repo>.git
unset GHT
```

## Notes

- Scripts were tested on sample data only (Linux). macOS and bash 3.2 are untested for the shell version.
- The wiki content belongs in a separate private repository; this repository holds only the skills.
