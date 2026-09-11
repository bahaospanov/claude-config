#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
SETTINGS="$CLAUDE/settings.json"
# Lets the next update replace an edited hook instead of stacking it beside the old one.
RECORD="$CLAUDE/hooks/state/installed-hooks.json"

command -v jq >/dev/null || { echo "update.sh: jq is required" >&2; exit 1; }
for bin in python3 git rsync; do
  command -v "$bin" >/dev/null || echo "warning: $bin not found" >&2
done

mkdir -p "$CLAUDE/hooks/state"
rsync -a --prune-empty-dirs --exclude '*.md' "$REPO/hooks/" "$CLAUDE/hooks/"

new=$(mktemp); tmp=$(mktemp)
trap 'rm -f "$new" "$tmp"' EXIT

files='{}'
while IFS= read -r ref; do
  files=$(jq --arg r "$ref" --rawfile t "$REPO/$ref" '. + {($r): $t}' <<<"$files")
done < <(jq -r '.. | .prompt? | strings | select(startswith("@")) | .[1:]' "$REPO/hooks.json")
jq --argjson files "$files" '
  walk(if type == "object" and (.prompt | type) == "string" and (.prompt | startswith("@"))
    then .prompt = ($files[.prompt[1:]] | if endswith("\n") then .[:-1] else . end)
    else . end)
' "$REPO/hooks.json" > "$new"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
prev=$(cat "$RECORD" 2>/dev/null || echo '{}')
# norm must stay identical to dump.sh, or groups already in settings.json get duplicated.
jq --arg home "$HOME" --arg q "'" --argjson prev "$prev" --slurpfile new "$new" '
  def norm: walk(if type == "object" and (.command | type) == "string"
    then .command |= (split($q + $home) | join("\"$HOME\"" + $q) | split($home) | join("$HOME"))
    else . end);
  def handlers($groups): [$groups[]? | .matcher as $m | .hooks[] | {m: $m, h: .}];
  $new[0] as $n
  | (.hooks // {}) as $cur
  | .hooks = (reduce ([$cur, $prev, $n] | map(keys[]) | unique[]) as $e ({};
      (handlers($prev[$e]) + handlers($n[$e])) as $drop
      | .[$e] = [($cur[$e] // [])[] | .matcher as $m
                 | .hooks |= map(select(norm as $x | any($drop[]; .m == $m and .h == $x) | not))
                 | select(.hooks != [])]
                + ($n[$e] // [])))
  | .hooks |= with_entries(select(.value != []))
' "$SETTINGS" > "$tmp"

if cmp -s "$tmp" "$SETTINGS"; then
  echo "settings.json already up to date"
else
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
  cat "$tmp" > "$SETTINGS"
  echo "settings.json updated (backup saved next to it)"
fi
cp "$new" "$RECORD"

jq -r '.[][].hooks[].command // empty' "$REPO/hooks.json" | tr -d "\"'" \
  | { grep -oE '(\$HOME)?/[A-Za-z0-9._/-]+' || true; } | sort -u \
  | while read -r p; do
      p="${p/#\$HOME/$HOME}"
      [ -e "$p" ] || echo "warning: hooks.json calls $p, which does not exist" >&2
    done

echo "done - restart running Claude Code sessions to load the hooks"
