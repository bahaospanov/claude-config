#!/usr/bin/env bash
# PreToolUse hook on Bash that blocks `git commit` / `git push` unless the
# user's most recent message contains an authorizing keyword. Enforces
# feedback_no_unprompted_ship.md mechanically — memory alone wasn't enough.
#
# stdin payload (Claude Code PreToolUse):
#   {
#     "tool_name": "Bash",
#     "tool_input": { "command": "..." },
#     "transcript_path": "/path/to/session-transcript.jsonl"
#   }
#
# Authorizing tokens (case-insensitive, word-boundary): commit, push, ship,
# deploy, merge. Exit 0 = allow; exit 2 = block with reason printed to stderr.

set -euo pipefail

payload=$(cat)

# Defensive: some harness builds deliver the payload double-encoded
# (a JSON string that itself contains the JSON object). If the top-level
# value parses as a string, decode once before extracting fields.
if [ "$(jq -r 'type' <<<"$payload" 2>/dev/null)" = "string" ]; then
  payload=$(jq -r '.' <<<"$payload")
fi

cmd=$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null || echo "")

# Only guard the two ship-equivalent verbs. Skim quickly so we don't pay
# transcript-parsing cost on every Bash call.
if ! grep -qE '(^|[[:space:]&;|(])git[[:space:]]+(commit|push)([[:space:]]|$)' <<<"$cmd"; then
  exit 0
fi

transcript=$(jq -r '.transcript_path // ""' <<<"$payload")

# Some harness builds omit .transcript_path. Reconstruct from session_id + cwd
# using Claude's canonical project layout: ~/.claude/projects/<encoded-cwd>/<session_id>.jsonl
if [ -z "$transcript" ] || [ ! -r "$transcript" ]; then
  sid=$(jq -r '.session_id // ""' <<<"$payload")
  cwd=$(jq -r '.cwd // ""' <<<"$payload")
  if [ -n "$sid" ]; then
    if [ -n "$cwd" ]; then
      enc=$(printf '%s' "$cwd" | sed 's|/|-|g; s|\.|-|g')
      candidate="$HOME/.claude/projects/$enc/$sid.jsonl"
      [ -r "$candidate" ] && transcript="$candidate"
    fi
    # Fallback: the session may be stored under a sibling project dir
    # (e.g. when running inside a git worktree, the transcript lives in
    # the original repo's project dir). Search for the session_id.
    if [ -z "$transcript" ] || [ ! -r "$transcript" ]; then
      found=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$sid.jsonl" -print -quit 2>/dev/null)
      [ -n "$found" ] && [ -r "$found" ] && transcript="$found"
    fi
  fi
fi

if [ -z "$transcript" ] || [ ! -r "$transcript" ]; then
  # Fail safe: no transcript = can't verify intent = block.
  echo "git-commit-guard: cannot read transcript; blocking $cmd" >&2
  exit 2
fi

# Worktree edge case: when the agent runs inside a git worktree, Claude
# Code routes some events (e.g. subagent metadata) to a transcript at the
# worktree's cwd-encoded path while the user-typed conversation stays in
# the parent repo's transcript. The candidate-by-cwd lookup above picks
# the metadata-only file first. Fall back to any sibling with the same
# session_id that does contain real user prompts.
_count_user_events() {
  awk '/"type":"user"/ && !/"tool_use_id"/ && !/"tool_result"/ {c++} END {print c+0}' "$1" 2>/dev/null
}

if [ "$(_count_user_events "$transcript")" -eq 0 ]; then
  sid_pick=$(jq -r '.session_id // ""' <<<"$payload" 2>/dev/null || echo "")
  if [ -n "$sid_pick" ]; then
    while IFS= read -r alt; do
      if [ "$alt" != "$transcript" ] && [ -r "$alt" ] && [ "$(_count_user_events "$alt")" -gt 0 ]; then
        transcript="$alt"
        break
      fi
    done < <(find "$HOME/.claude/projects" -maxdepth 2 -name "$sid_pick.jsonl" 2>/dev/null)
  fi
fi

# Pull the last few user *prompts* from the JSONL transcript. Each line is
# one event; both real user prompts AND tool results are emitted with
# type=user, so we must exclude tool_result entries — otherwise the hook
# picks up the last Bash tool's output instead of the human's message and
# wrongly blocks (e.g. running `npm test` between "ship" and `git commit`
# would hide the authorization).
#
# Why the last 3 (not just 1): a one-shot "commit and push" is often
# followed by a clarifying reply ("yes", a task ID like "77", a branch
# name) before the assistant actually commits. Looking only at the most
# recent message would invalidate the original authorization. Three is a
# pragmatic window — long enough for two follow-ups, short enough that
# stale "commit" instructions from earlier in the conversation don't
# leak through. Tightening this is safer than widening it.
USER_LOOKBACK=3

reverse_transcript() {
  tac "$transcript" 2>/dev/null || tail -r "$transcript" 2>/dev/null
}

recent_user_events=$(reverse_transcript \
  | awk -v n="$USER_LOOKBACK" '
      /"type":"user"/ && !/"tool_use_id"/ && !/"tool_result"/ {
        print
        if (++c >= n) exit
      }' || true)

if [ -z "$recent_user_events" ]; then
  echo "git-commit-guard: no user message found in transcript; blocking" >&2
  exit 2
fi

# Extract text from each recent event and concatenate. message.content can
# be a string or an array of {type:"text",text:"..."} blocks; jq handles
# both. We OR the windows together — any one carrying an authorizing
# keyword authorizes the whole sequence.
text=$(jq -rs '
  map(
    .message.content
    | if type == "string" then .
      elif type == "array" then map(select(.type == "text") | .text) | join(" ")
      else "" end
  ) | join("\n")
' <<<"$recent_user_events" 2>/dev/null || echo "")

# Authorizing tokens. Word-boundary, case-insensitive.
# "pr" / "PR" implies push: opening or updating a PR requires the branch
# to be on the remote, so a force-push during rebase is in scope.
if grep -qiE '(^|[^a-zA-Z])(commit|push|ship|deploy|merge|pr)([^a-zA-Z]|$)' <<<"$text"; then
  exit 0
fi

cat >&2 <<EOF
git-commit-guard: blocking '$cmd' — the most recent user message does not
contain an authorizing keyword (commit/push/ship/deploy/merge/pr). Per the
no-unprompted-ship rule (memory: feedback_no_unprompted_ship.md), do NOT
commit or push without explicit instruction in the current turn. Stop,
state what is ready, and wait for the user to authorize.
EOF
exit 2
