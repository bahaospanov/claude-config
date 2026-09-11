# claude-config

Global Claude Code hooks, in a form that can be committed and reinstalled:
the scripts from `~/.claude/hooks/` and the `hooks` block of
`~/.claude/settings.json`. Nothing else from `settings.json` lives here.

    hooks/
      comment-guard/      comment-guard.py, comment-diff-guard.py, comment_rules.py
      commit-guard/       git-commit-guard.sh
      commit-message/     commit-message-guard.py, judge.md
      mr-description/     mr-description-guard.py
      doc-judge/          prompt.md
      script-judge/       prompt.md
    hooks.json            the hooks block, home directory written as $HOME
    dump.sh               ~/.claude -> repo
    update.sh             repo -> ~/.claude

The `.md` files hold the text of prompt hooks, which get pasted into
settings.json on install and are never copied into ~/.claude/hooks.

## Use

After editing hooks on your machine, run:

    ./dump.sh && git diff

On a new machine, or to install these hooks for someone else, run:

    git clone <this repo> && cd claude-config && ./update.sh

`update.sh` does three things:

- copies the scripts
- merges `hooks.json` into `settings.json`, keeping hooks that didn't come
  from here and replacing ones an earlier update added
- saves `settings.json.bak.<time>` before changing anything

Then restart any open Claude Code sessions.

## Requirements

You need `bash`, `jq`, `python3`, `git` and `rsync`. macOS ships all of
them, with `python3` coming from the Xcode command line tools.

## What the hooks do

- `comment-guard/` flags edits that add many comments or leave a region
  dense with them. It runs once after each Write/Edit, and again at the end
  of each turn against the git diff, which catches edits made through Bash.
- `commit-guard/` blocks git commit and push unless the latest user
  message asks for it. It also supports commit grants and per-repo
  protected branches through `.claude/push-policy.json`.
- `commit-message/` requires a Conventional Commits prefix, and a Haiku
  judge (`judge.md`) reviews the message itself.
- `mr-description/` enforces the MR/PR description format.
- `doc-judge/` is a Haiku judge for new or grown Markdown docs.
- `script-judge/` is a Haiku judge for new script files.
