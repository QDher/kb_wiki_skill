# kb - knowledge wiki

## Variables (set per account in ~/.bashrc)
```bash
export KB_ROOT=$HOME/kb
export PROJECT=def-<pi>            # Slurm account / project allocation
# $USER, $HOME, $SCRATCH are set by the cluster
```

## Setup on a new account or machine
```bash
git clone <repo-url> "$KB_ROOT"
mkdir -p ~/.claude/skills && cp -r "$KB_ROOT/.claude/skills/kb-wiki" ~/.claude/skills/   # if the skill is stored in the repo
echo '@'"$KB_ROOT"'/CLAUDE.md' >> ~/.claude/CLAUDE.md   # Claude Code loads wiki rules in every session
```

## claude.ai Projects
- Project instructions: content of `CLAUDE.md`.
- Project knowledge: `INDEX.md` + the relevant `projects/<name>/` and `workflows/` pages. Re-upload after changes.

## Update
`git pull` before work; after a session run the kb-wiki skill `update` mode; `git push`.

## Layout
`rules/ workflows/ projects/ knowledge/ reference/ archive/ raw/` - see INDEX.md. `raw/` is not committed.
