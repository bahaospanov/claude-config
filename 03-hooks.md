# Hooks — reinstall reference

> **Claude-Code-only.** Other LLM agents don't have a hook system. The behavior this hook enforces is already self-enforced via [[01-rules]] — agents without hooks just follow the rule directly.

## `git-commit-guard.sh` (PreToolUse on Bash)

Mechanical enforcement of the keyword-authorization rule. Blocks `git commit` / `git push` unless one of `commit | push | ship | deploy | merge | pr` appears in any of the last 3 user messages. Exit 0 = allow, exit 2 = block with stderr reason.

Full script lives at `claude-config/hooks/git-commit-guard.sh`.

### Install

```bash
mkdir -p ~/.claude/hooks
cp claude-config/hooks/git-commit-guard.sh ~/.claude/hooks/git-commit-guard.sh
chmod +x ~/.claude/hooks/git-commit-guard.sh
```

### Wire into `~/.claude/settings.json`

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/hooks/git-commit-guard.sh",
            "if": "Bash(git *)"
          }
        ]
      }
    ]
  }
}
```

### Dependencies

`jq`, `awk`, `grep`, `find`, plus either `tac` (Linux) or `tail -r` (macOS — the script tries both).
