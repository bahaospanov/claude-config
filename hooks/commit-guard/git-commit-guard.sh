#!/usr/bin/env bash
# PreToolUse hook on Bash that blocks `git commit` / `git push` unless the
# call is authorized. Enforces feedback_no_unprompted_ship.md mechanically —
# memory alone wasn't enough.
#
# Two ways to authorize:
#   1. Keyword in the user's most recent message (commit/push/ship/deploy/
#      merge/pr). Always sufficient, for both verbs.
#   2. A standing *commit grant*: a pre-approved budget of commits for the
#      session, so a multi-task run or a goal-scoped skill can commit between
#      user turns. Grants cover `git commit` ONLY — `git push` always needs a
#      keyword in the current message, because a push is a deploy.
#
# On top of that, a repo may declare *protected push targets* (see
# .claude/push-policy.json below). A bare "push" authorizes pushing a feature
# branch; it does NOT authorize pushing straight to an integration branch,
# because that bypasses the PR flow. Those need the user to name the branch:
# "push to dev". Repos without a policy file are unaffected.
#
# Grants are created either by the hook itself (when the user's message asks
# for repeated commits: "commit after each task", "commit x5", ...) or by
# `git-commit-guard.sh grant`, which refuses unless some recent user message
# in the session already authorized shipping. The model can therefore widen
# an authorization the user gave, never invent one.
#
# stdin payload (Claude Code PreToolUse):
#   {
#     "tool_name": "Bash",
#     "tool_input": { "command": "..." },
#     "transcript_path": "/path/to/session-transcript.jsonl"
#   }
#
# Exit 0 = allow; exit 2 = block with reason printed to stderr.
#
# CLI (no stdin):
#   git-commit-guard.sh grant [--uses N] [--ttl SECONDS] [--goal TEXT]
#                             [--session ID] [--cwd PATH]
#   git-commit-guard.sh status [--session ID]
#   git-commit-guard.sh revoke [--session ID]

set -euo pipefail

GRANT_DIR="${CLAUDE_COMMIT_GRANT_DIR:-$HOME/.claude/hooks/state/commit-grants}"
GRANT_DEFAULT_USES=5        # "commit after each task" and friends
GRANT_SESSION_USES=10       # "for the rest of the session"
GRANT_MAX_USES=20
GRANT_DEFAULT_TTL=7200      # 2h
GRANT_MAX_TTL=28800         # 8h
GRANT_PRUNE_MIN=1440        # drop grant files older than 24h

# Authorizing tokens. Word-boundary, case-insensitive.
# "pr" / "PR" implies push: opening or updating a PR requires the branch to be
# on the remote, so a force-push during rebase is in scope.
AUTH_RE='(^|[^a-zA-Z])(commit|push|ship|deploy|merge|pr)([^a-zA-Z]|$)'

# Merging an MR is a deploy with no approval gate behind it, so it gets its own
# narrower keyword: "ship" and "push" authorize landing work on the BRANCH.
MERGE_RE='(merge_requests/[0-9]+/merge|pulls/[0-9]+/merge|(^|[[:space:]&;|(])(gh[[:space:]]+pr|glab[[:space:]]+mr)[[:space:]]+merge([[:space:]]|$))'
MERGE_AUTH_RE='(^|[^a-zA-Z])(merge|merging|смерж[а-яё]*|влей|влить|вмерж[а-яё]*)([^a-zA-Z]|$)'

# Only the most recent user message authorizes a keyword-based pass: a stale
# "ship" from an earlier turn must not green-light an unrelated follow-up.
# Grants exist precisely to cover the multi-turn case, under a budget.
USER_LOOKBACK=1
# The CLI gate is deliberately wider — it only asks "did the user ever ask for
# commits in this session", and the grant it writes is still bounded.
CLI_LOOKBACK=30

now() { date +%s; }

encode_cwd() { printf '%s' "$1" | sed 's|/|-|g; s|\.|-|g'; }

_count_user_events() {
  awk '/"type":"user"/ && !/"tool_use_id"/ && !/"tool_result"/ {c++} END {print c+0}' "$1" 2>/dev/null
}

_reverse_file() { tac "$1" 2>/dev/null || tail -r "$1" 2>/dev/null; }

# Pull the text of the last N user *prompts*. Both real prompts AND tool
# results are emitted with type=user, so tool_result entries must be excluded —
# otherwise the last Bash tool's output stands in for the human's message
# (e.g. running `npm test` between "ship" and `git commit` would hide the
# authorization). message.content is a string or an array of text blocks.
recent_user_text() { # $1=transcript $2=n
  local events
  events=$(_reverse_file "$1" \
    | awk -v n="$2" '
        /"type":"user"/ && !/"tool_use_id"/ && !/"tool_result"/ {
          print
          if (++c >= n) exit
        }' || true)
  [ -n "$events" ] || return 1
  jq -rs '
    map(
      .message.content
      | if type == "string" then .
        elif type == "array" then map(select(.type == "text") | .text) | join(" ")
        else "" end
    ) | join("\n")
  ' <<<"$events" 2>/dev/null || return 1
}

# Locate the session transcript. Claude's canonical layout is
# ~/.claude/projects/<encoded-cwd>/<session_id>.jsonl, but some harness builds
# omit .transcript_path, and inside a git worktree the user-typed conversation
# can live under the parent repo's project dir while a metadata-only file sits
# at the worktree's encoded path. So: hint, then cwd candidate, then any
# sibling with the same session id — preferring one that has real prompts.
find_transcript() { # $1=hint $2=sid $3=cwd
  local hint="${1:-}" sid="${2:-}" cwd="${3:-}" t="" cand="" found="" alt=""
  if [ -n "$hint" ] && [ -r "$hint" ]; then t="$hint"; fi
  if [ -z "$t" ] && [ -n "$sid" ]; then
    if [ -n "$cwd" ]; then
      cand="$HOME/.claude/projects/$(encode_cwd "$cwd")/$sid.jsonl"
      if [ -r "$cand" ]; then t="$cand"; fi
    fi
    if [ -z "$t" ]; then
      found=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$sid.jsonl" -print -quit 2>/dev/null || true)
      if [ -n "$found" ] && [ -r "$found" ]; then t="$found"; fi
    fi
  fi
  if [ -n "$t" ] && [ "$(_count_user_events "$t")" -eq 0 ] && [ -n "$sid" ]; then
    while IFS= read -r alt; do
      if [ "$alt" != "$t" ] && [ -r "$alt" ] && [ "$(_count_user_events "$alt")" -gt 0 ]; then
        t="$alt"
        break
      fi
    done < <(find "$HOME/.claude/projects" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null || true)
  fi
  [ -n "$t" ] || return 1
  printf '%s' "$t"
}

grant_path() { printf '%s/%s.json' "$GRANT_DIR" "$1"; }

grant_prune() {
  find "$GRANT_DIR" -type f -name '*.json' -mmin "+$GRANT_PRUNE_MIN" -delete 2>/dev/null || true
}

text_fingerprint() { # $1=text
  printf '%s' "$1" | { shasum 2>/dev/null || cksum; } | awk '{print $1}'
}

grant_write() { # $1=sid $2=uses $3=ttl $4=goal $5=source $6=cwd [$7=fingerprint]
  local sid="$1" uses="$2" ttl="$3" goal="$4" source="$5" cwd="$6" fp="${7:-}" n tmp gp
  if [ "$uses" -gt "$GRANT_MAX_USES" ]; then uses=$GRANT_MAX_USES; fi
  if [ "$ttl" -gt "$GRANT_MAX_TTL" ]; then ttl=$GRANT_MAX_TTL; fi
  mkdir -p "$GRANT_DIR" 2>/dev/null || return 1
  n=$(now)
  gp=$(grant_path "$sid")
  tmp="$gp.tmp.$$"
  # cwd is metadata only: a git worktree legitimately commits from a different
  # directory than the one the session started in. session_id is the scope.
  jq -n \
    --arg sid "$sid" --arg goal "$goal" --arg src "$source" --arg cwd "$cwd" --arg fp "$fp" \
    --argjson uses "$uses" --argjson created "$n" --argjson exp "$((n + ttl))" \
    '{session_id:$sid, scope:"commit", uses_remaining:$uses,
      created_at:$created, expires_at:$exp, goal:$goal, source:$src, cwd:$cwd,
      prompt_fingerprint:$fp}' \
    >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$gp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  printf '%s' "$uses"
}

# Spend one use. Echoes "<remaining>|<goal>" on success, nonzero if no valid
# grant covers the call.
grant_consume() { # $1=sid
  local sid="${1:-}" gp exp uses scope goal left tmp
  [ -n "$sid" ] || return 1
  gp=$(grant_path "$sid")
  [ -r "$gp" ] || return 1
  exp=$(jq -r '.expires_at // 0' "$gp" 2>/dev/null || echo 0)
  uses=$(jq -r '.uses_remaining // 0' "$gp" 2>/dev/null || echo 0)
  scope=$(jq -r '.scope // "commit"' "$gp" 2>/dev/null || echo commit)
  goal=$(jq -r '.goal // ""' "$gp" 2>/dev/null || echo "")
  [[ "$exp" =~ ^[0-9]+$ ]] || return 1
  [[ "$uses" =~ ^[0-9]+$ ]] || return 1
  [ "$scope" = "commit" ] || return 1
  [ "$exp" -gt "$(now)" ] || return 1
  [ "$uses" -gt 0 ] || return 1
  left=$((uses - 1))
  tmp="$gp.tmp.$$"
  jq --argjson u "$left" --argjson t "$(now)" \
     '.uses_remaining=$u | .last_used_at=$t' "$gp" >"$tmp" 2>/dev/null \
     || { rm -f "$tmp"; return 1; }
  mv "$tmp" "$gp" 2>/dev/null || { rm -f "$tmp"; return 1; }
  printf '%s|%s' "$left" "$goal"
}

# Does the user's message ask for repeated commits? Echoes a use count, or
# nothing. Explicit count wins, then session-wide, then per-task phrasing.
parse_grant_request() { # $1=text
  local t n
  t=$(tr '\n' ' ' <<<"$1")

  n=$(sed -nE 's/.*[Cc]ommits?[[:space:]]*[xX*][[:space:]]*([0-9]+).*/\1/p' <<<"$t" | head -n1)
  [ -z "$n" ] && n=$(sed -nE 's/.*[Кк]оммит[а-яА-Я]*[[:space:]]*[xXхХ*][[:space:]]*([0-9]+).*/\1/p' <<<"$t" | head -n1)
  [ -z "$n" ] && n=$(sed -nE 's/.*[^0-9]([0-9]+)[[:space:]]+(separate[[:space:]]+)?[Cc]ommits.*/\1/p' <<<"$t" | head -n1)
  [ -z "$n" ] && n=$(sed -nE 's/.*[^0-9]([0-9]+)[[:space:]]+[Кк]оммит[а-яА-Я]*.*/\1/p' <<<"$t" | head -n1)
  if [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null; then
    printf '%s' "$n"
    return 0
  fi

  if grep -qiE '(rest of (the |this )?session|until I (say|tell)|keep committing|до конца сесси)' <<<"$t"; then
    printf '%s' "$GRANT_SESSION_USES"
    return 0
  fi

  if grep -qiE '(auto-?commit|commit (after|between|per|each|every|as you go|along the way)|(after|between) each (task|step|part|item|fix)[^.]{0,40}commit|one commit per|separate commits|commit them separately|коммит[а-я]* (после|на) кажд|коммить по ходу|отдельны[емх] коммит)' <<<"$t"; then
    printf '%s' "$GRANT_DEFAULT_USES"
    return 0
  fi

  return 1
}

# --------------------------------------------------- protected push targets --
#
# Per-repo policy at <repo-root>/.claude/push-policy.json:
#   { "protected_branches": ["dev", "main"] }
# Absent, unreadable or empty → nothing is protected and this whole section is
# inert, so the hook's behavior in every other project is unchanged.

policy_branches() { # $1=cwd
  local cwd="${1:-}" top pol
  [ -n "$cwd" ] || return 1
  top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || return 1
  pol="$top/.claude/push-policy.json"
  [ -r "$pol" ] || return 1
  jq -r '.protected_branches[]? // empty' "$pol" 2>/dev/null
}

# Branch names a `git push` would write to, one per line. Nonzero when the
# destination can't be determined, so the caller can fail safe.
push_targets() { # $1=command $2=cwd
  local cmd="$1" cwd="${2:-.}" t cur i n found=0
  local -a toks
  # Newlines separate commands just like `;` does. Rewriting them as explicit
  # separators is also what makes tokenizing work at all: `read -a` stops at the
  # first line, so a push on any later line was previously invisible.
  local flat=${cmd//$'\n'/ ; }
  read -r -a toks <<<"$flat"
  n=${#toks[@]}

  # Every `git push` in the command, not just the first — otherwise
  # `git push origin feature && git push origin dev` is judged on the harmless
  # half and the protected one rides along behind it.
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${toks[i]}" != "git" ] || [ $((i + 1)) -ge "$n" ] || [ "${toks[i + 1]}" != "push" ]; then
      i=$((i + 1))
      continue
    fi
    found=1
    i=$((i + 2))

    local remote_seen=0 all=0
    local -a refs=()
    while [ "$i" -lt "$n" ]; do
      t="${toks[i]}"
      case "$t" in
        '&&' | '||' | ';' | '|') break ;;                      # next command starts here
        --all | --mirror) all=1 ;;                             # pushes every branch
        --repo | --push-option | --receive-pack | --exec | -o) i=$((i + 1)) ;;  # flag + value
        -*) ;;                                                 # any other flag
        *) if [ "$remote_seen" = 0 ]; then remote_seen=1; else refs+=("$t"); fi ;;
      esac
      i=$((i + 1))
    done

    if [ "$all" = 1 ]; then
      printf '%s\n' '*'   # matches whatever the repo protects
    elif [ ${#refs[@]} -eq 0 ]; then
      # No refspec (`git push`, `git push origin`): the destination is whatever
      # the current branch tracks, which for our purposes is its own name.
      cur=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
      [ -n "$cur" ] && [ "$cur" != "HEAD" ] || return 1
      printf '%s\n' "$cur"
    else
      for t in "${refs[@]}"; do
        t="${t#+}"            # forced refspec (+src:dst)
        t="${t##*:}"          # dst half of src:dst — also handles the :dst delete form
        t="${t#refs/heads/}"
        if [ "$t" = "HEAD" ]; then
          t=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null) || return 1
          [ "$t" != "HEAD" ] || return 1
        fi
        [ -n "$t" ] && printf '%s\n' "$t"
      done
    fi
  done

  [ "$found" = 1 ] || return 1
}

# Echoes the policy entry a target hits, nonzero if it hits none.
match_protected() { # $1=branch $2=policy-list
  local b="$1" p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if [ "$b" = '*' ] || [ "$b" = "$p" ]; then
      printf '%s' "$p"
      return 0
    fi
  done <<<"$2"
  return 1
}

# Did the user authorize a push to THIS branch by naming it? A generic "push"
# deliberately does not match — that is the whole point of the tier.
names_branch() { # $1=text $2=branch
  local esc
  esc=$(sed 's/[][\.^$*+?(){}|\\/-]/\\&/g' <<<"$2")
  grep -qiE '(push|ship|deploy|merge|пуш|запуш[а-я]*)[^.!?]{0,40}(^|[^a-z0-9_/-])'"$esc"'([^a-z0-9_/-]|$)' <<<"$1"
}

# ---------------------------------------------------------------- CLI mode --

cli_usage() {
  cat <<'EOF'
git-commit-guard.sh — pre-authorized commit grants

  grant [--uses N] [--ttl SECONDS] [--goal TEXT] [--session ID] [--cwd PATH]
        Pre-authorize N `git commit` calls for the session (default 5, max 20)
        for TTL seconds (default 7200, max 28800). Refused unless a recent
        user message in the session contains an authorizing keyword
        (commit/push/ship/deploy/merge/pr). Never covers `git push`.

  status [--session ID]     Show the current grant and whether it is live.
  revoke [--session ID]     Drop the grant.

Session id resolution: --session, then $CLAUDE_SESSION_ID, then the most
recently modified transcript for the current directory.
EOF
}

cli_resolve_session() { # $1=sid-or-empty $2=cwd
  local sid="${1:-}" cwd="$2" dir newest
  if [ -n "$sid" ]; then printf '%s' "$sid"; return 0; fi
  if [ -n "${CLAUDE_SESSION_ID:-}" ]; then printf '%s' "$CLAUDE_SESSION_ID"; return 0; fi
  dir="$HOME/.claude/projects/$(encode_cwd "$cwd")"
  newest=$(ls -t "$dir"/*.jsonl 2>/dev/null | head -n1 || true)
  if [ -z "$newest" ]; then
    newest=$(ls -t "$HOME"/.claude/projects/*/*.jsonl 2>/dev/null | head -n1 || true)
  fi
  [ -n "$newest" ] || return 1
  basename "$newest" .jsonl
}

cli_main() {
  local sub="$1"; shift
  local uses="$GRANT_DEFAULT_USES" ttl="$GRANT_DEFAULT_TTL" goal="" sid="" cwd="$PWD"
  while [ $# -gt 0 ]; do
    case "$1" in
      --uses)    uses="${2:-}"; shift 2 ;;
      --ttl)     ttl="${2:-}"; shift 2 ;;
      --goal)    goal="${2:-}"; shift 2 ;;
      --session) sid="${2:-}"; shift 2 ;;
      --cwd)     cwd="${2:-}"; shift 2 ;;
      -h|--help) cli_usage; return 0 ;;
      *) echo "git-commit-guard: unknown flag '$1'" >&2; return 1 ;;
    esac
  done

  sid=$(cli_resolve_session "$sid" "$cwd" || true)
  if [ -z "$sid" ]; then
    echo "git-commit-guard: cannot resolve session id; pass --session" >&2
    return 1
  fi

  case "$sub" in
    status)
      local gp; gp=$(grant_path "$sid")
      if [ ! -r "$gp" ]; then echo "no grant for session $sid"; return 0; fi
      jq --argjson t "$(now)" \
         '. + {live: (.uses_remaining > 0 and .expires_at > $t), seconds_left: (.expires_at - $t)}' \
         "$gp"
      ;;
    revoke)
      rm -f "$(grant_path "$sid")"
      echo "git-commit-guard: grant revoked for session $sid"
      ;;
    grant)
      [[ "$uses" =~ ^[0-9]+$ ]] && [ "$uses" -gt 0 ] || { echo "git-commit-guard: --uses must be a positive integer" >&2; return 1; }
      [[ "$ttl" =~ ^[0-9]+$ ]] && [ "$ttl" -gt 0 ] || { echo "git-commit-guard: --ttl must be a positive integer" >&2; return 1; }

      local transcript text
      transcript=$(find_transcript "" "$sid" "$cwd" || true)
      if [ -z "$transcript" ]; then
        echo "git-commit-guard: no transcript for session $sid; refusing to grant" >&2
        return 1
      fi
      text=$(recent_user_text "$transcript" "$CLI_LOOKBACK" || true)
      if ! grep -qiE "$AUTH_RE" <<<"$text"; then
        cat >&2 <<EOF
git-commit-guard: refusing to grant — no authorizing keyword
(commit/push/ship/deploy/merge/pr) in the last $CLI_LOOKBACK user messages of
session $sid. A grant widens an authorization the user gave; it cannot create
one. Ask the user to authorize committing, then retry.
EOF
        return 1
      fi

      local written
      written=$(grant_write "$sid" "$uses" "$ttl" "$goal" "cli" "$cwd") || {
        echo "git-commit-guard: failed to write grant" >&2; return 1; }
      echo "git-commit-guard: granted $written commit(s) for ${ttl}s${goal:+ — goal: $goal} (session $sid)"
      ;;
    *)
      cli_usage; return 1 ;;
  esac
}

case "${1:-}" in
  grant|status|revoke) grant_prune; cli_main "$@"; exit $? ;;
  help|-h|--help)      cli_usage; exit 0 ;;
esac

# --------------------------------------------------------------- hook mode --

payload=$(cat)

# Defensive: some harness builds deliver the payload double-encoded (a JSON
# string that itself contains the JSON object). If the top-level value parses
# as a string, decode once before extracting fields.
if [ "$(jq -r 'type' <<<"$payload" 2>/dev/null)" = "string" ]; then
  payload=$(jq -r '.' <<<"$payload")
fi

cmd=$(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null || echo "")

# Quotes stripped first: a plain space must stay a command boundary below (or
# `time git commit` slips past), and that also matched prose merely quoting it.
scan=$(printf '%s' "$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

# Merging a PR/MR is not a git verb, so it used to miss this hook entirely.
# Matched on the RAW command: `scan` has quotes stripped and the URL lives in
# one. Merge outranks the others — a command that merges is a merge.
if grep -qE "$MERGE_RE" <<<"$cmd"; then
  verb=merge
elif grep -qE '(^|[[:space:]&;|(])git[[:space:]]+push([[:space:]]|$)' <<<"$scan"; then
  verb=push
elif grep -qE '(^|[[:space:]&;|(])git[[:space:]]+commit([[:space:]]|$)' <<<"$scan"; then
  verb=commit
else
  exit 0
fi

sid=$(jq -r '.session_id // ""' <<<"$payload" 2>/dev/null || echo "")
cwd=$(jq -r '.cwd // ""' <<<"$payload" 2>/dev/null || echo "")

grant_prune

if [ "$verb" = "commit" ]; then
  if grant_hit=$(grant_consume "$sid"); then
    left=${grant_hit%%|*}
    goal=${grant_hit#*|}
    echo "git-commit-guard: allowed by standing commit grant — $left use(s) left${goal:+, goal: $goal}"
    exit 0
  fi
fi

transcript=$(find_transcript "$(jq -r '.transcript_path // ""' <<<"$payload")" "$sid" "$cwd" || true)

if [ -z "$transcript" ] || [ ! -r "$transcript" ]; then
  # Fail safe: no transcript = can't verify intent = block.
  echo "git-commit-guard: cannot read transcript; blocking $cmd" >&2
  exit 2
fi

text=$(recent_user_text "$transcript" "$USER_LOOKBACK" || true)

if [ -z "$text" ]; then
  echo "git-commit-guard: no user message found in transcript; blocking" >&2
  exit 2
fi

if [ "$verb" = "merge" ]; then
  if grep -qiE "$MERGE_AUTH_RE" <<<"$text"; then
    exit 0
  fi
  cat >&2 <<EOF
git-commit-guard: blocking '$cmd' — merging needs the user to say "merge" in
their most recent message. "ship", "push", "commit", "deploy" and "pr" do NOT
authorize it: they authorize landing work on the BRANCH, and the user expects
to press merge themselves.

Merging into an integration branch is a deploy with no approval gate behind
it. Stop at the push, report the MR state, and let the user merge.

A tool call that a permission layer happens to let through is not the user
authorizing it. If an earlier call was blocked and a later identical one is
not, that is the sandbox changing its mind, not consent.
EOF
  exit 2
fi

# Protected targets are checked BEFORE the generic keyword pass — otherwise a
# bare "push" would exit 0 below and the destination would never be examined.
if [ "$verb" = "push" ]; then
  policy=$(policy_branches "$cwd" 2>/dev/null || true)
  if [ -n "$policy" ]; then
    protected=""
    if targets=$(push_targets "$cmd" "$cwd"); then
      while IFS= read -r tgt; do
        [ -n "$tgt" ] || continue
        if hit=$(match_protected "$tgt" "$policy"); then
          protected="$hit"
          break
        fi
      done <<<"$targets"
    else
      cat >&2 <<EOF
git-commit-guard: cannot determine the destination branch of '$cmd', and this
repo protects branches ($(tr '\n' ' ' <<<"$policy")). Re-run with an explicit
refspec so the destination is unambiguous, e.g.
  git push origin <branch>
EOF
      exit 2
    fi

    if [ -n "$protected" ]; then
      if names_branch "$text" "$protected"; then
        echo "git-commit-guard: direct push to '$protected' — authorized by name in the user's message"
        exit 0
      fi
      cat >&2 <<EOF
git-commit-guard: blocking '$cmd' — '$protected' is a protected branch in this
repo (.claude/push-policy.json) and the user's most recent message does not
name it. A bare "push" authorizes pushing a feature branch, not a direct push
to an integration branch: that bypasses the PR flow.

Default path — push the feature branch and open a PR:
  git push -u origin <feature-branch>
  gh pr create --base $protected

If a direct push is genuinely wanted, the user must say so by name, e.g.
"push to $protected". Ask them; do not paraphrase your way around this.

Note: this reads the user's most recent *persisted* message. A message sent
mid-turn (while you were already working) is not visible here — if the user
authorized that way, ask them to resend it as its own message.
EOF
      exit 2
    fi
  fi
fi

if grep -qiE "$AUTH_RE" <<<"$text"; then
  # The same message may also ask for repeated commits. Open a grant so the
  # rest of the run doesn't need the keyword repeated, and charge this call
  # against it so "commit x3" means three commits, not three plus this one.
  # Fingerprint the message: while it stays the most recent one, every commit
  # would otherwise refill the budget it is supposed to be spending.
  if [ "$verb" = "commit" ] && [ -n "$sid" ]; then
    if req=$(parse_grant_request "$text"); then
      fp=$(text_fingerprint "$text")
      prev_fp=$(jq -r '.prompt_fingerprint // ""' "$(grant_path "$sid")" 2>/dev/null || echo "")
      prev_exp=$(jq -r '.expires_at // 0' "$(grant_path "$sid")" 2>/dev/null || echo 0)
      if [ "$fp" = "$prev_fp" ] && [ "$prev_exp" -gt "$(now)" ] 2>/dev/null; then
        exit 0
      fi
      if grant_write "$sid" "$req" "$GRANT_DEFAULT_TTL" "" "prompt" "$cwd" "$fp" >/dev/null; then
        hit=$(grant_consume "$sid" || true)
        echo "git-commit-guard: user message opens a commit grant — ${hit%%|*} further commit(s) allowed for $((GRANT_DEFAULT_TTL / 60))m"
      fi
    fi
  fi
  exit 0
fi

cat >&2 <<EOF
git-commit-guard: blocking '$cmd' — the most recent user message does not
contain an authorizing keyword (commit/push/ship/deploy/merge/pr) and no
standing commit grant covers this call. Per the no-unprompted-ship rule
(memory: feedback_no_unprompted_ship.md), do NOT commit or push without
explicit instruction in the current turn. Stop, state what is ready, and wait
for the user to authorize.

If the user already authorized repeated commits earlier in this session (e.g.
a multi-task run or a goal-scoped skill), pre-authorize with:
  $HOME/.claude/hooks/commit-guard/git-commit-guard.sh grant --uses N --goal "<goal>"
That covers \`git commit\` only — \`git push\` always needs a keyword in the
current message.
EOF
exit 2
