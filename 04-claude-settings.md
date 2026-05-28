# Claude Code global settings — reinstall reference

> **Claude-Code-only.** Other LLM agents ignore. Settings live verbatim under `claude-config/`.

## Files

| Dump path                                  | Restore to                                | Purpose                                                                 |
| ------------------------------------------ | ----------------------------------------- | ----------------------------------------------------------------------- |
| `claude-config/settings.json`              | `~/.claude/settings.json`                 | Global config: MCP allowlist, hooks, status line, plugins, model prefs  |
| `claude-config/hooks/git-commit-guard.sh`  | `~/.claude/hooks/git-commit-guard.sh`     | PreToolUse hook for `Bash(git *)` — body documented in [[03-hooks]]     |

`~/.claude/settings.local.json` is intentionally not dumped — it's machine-local permission allowlist that's safer to rebuild on demand than to restore from a snapshot.

## Restore

```bash
mkdir -p ~/.claude/hooks
cp claude-config/settings.json              ~/.claude/settings.json
cp claude-config/hooks/git-commit-guard.sh  ~/.claude/hooks/git-commit-guard.sh
chmod +x ~/.claude/hooks/git-commit-guard.sh
```

## What's inside `settings.json`

- **`permissions.allow`** — pre-approved MCP tools (playwright, codegraph reads)
- **`hooks.PreToolUse`** — `git-commit-guard.sh` runs before any `Bash(git *)` call (see [[03-hooks]])
- **`statusLine`** — shell one-liner rendering `<folder>  <branch>  <model>`
- **`enabledPlugins`** — caveman, karpathy-skills (see [[02-plugins]])
- **`extraKnownMarketplaces`** — GitHub sources for caveman + karpathy-skills marketplaces
- **`alwaysThinkingEnabled`: true** — extended thinking on by default
- **`effortLevel`: "xhigh"** — max reasoning effort
- **`skipDangerousModePermissionPrompt`: true** — no nag on `--dangerously-skip-permissions`
- **`skipAutoPermissionPrompt`: true** — auto-allow prompts dismissed
- **`agentPushNotifEnabled`: true** — push notifications on agent completion

## When to re-export

Re-run the dump whenever you:
- toggle a plugin (`/plugin`)
- add an MCP server permission you want to keep
- change the status line or hook script
- bump `effortLevel` / thinking prefs

Source of truth is `~/.claude/settings.json` — re-copy it into `claude-config/` to refresh this dump.
