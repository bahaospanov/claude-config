#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
CLAUDE="$HOME/.claude"
EXTERNAL=(herdr-agent-state.sh moshi-hook)

command -v jq >/dev/null || { echo "dump.sh: jq is required" >&2; exit 1; }
[ -d "$CLAUDE/hooks" ] || { echo "dump.sh: $CLAUDE/hooks not found" >&2; exit 1; }

# hooks/**/*.md are prompt files that exist only in the repo; --delete would wipe them.
rsync -a --delete --exclude state/ --exclude __pycache__/ --exclude .DS_Store --exclude '*.md' \
  "${EXTERNAL[@]/#/--exclude=}" "$CLAUDE/hooks/" "$REPO/hooks/"

out=$(mktemp)
trap 'rm -f "$out"' EXIT
# '/Users/x/...' becomes "$HOME"'/...': $HOME inside single quotes never expands.
# update.sh matches existing groups with the same norm; keep the two identical.
jq --arg home "$HOME" --arg q "'" --arg ext "${EXTERNAL[*]}" \
   --argjson prev "$(cat "$REPO/hooks.json" 2>/dev/null || echo '{}')" '
  def norm: walk(if type == "object" and (.command | type) == "string"
    then .command |= (split($q + $home) | join("\"$HOME\"" + $q) | split($home) | join("$HOME"))
    else . end);
  # Rename a statusMessage in hooks.json + update.sh; renamed only in settings.json, its file is lost.
  def pkey($e; $m): [$e, $m, .statusMessage] | tojson;
  def prompts: to_entries[] | .key as $e | .value[] | .matcher as $m | .hooks[]
    | select(.type == "prompt") | {k: pkey($e; $m), p: .prompt};
  ([$prev | prompts | select(.p | startswith("@")) | {(.k): .p[1:]}] | add // {}) as $refs
  | (.hooks // {} | norm
      | map_values(map(.hooks |= map(select((.command // "") as $c
                                     | any($ext | split(" ")[]; . as $x | $c | contains($x)) | not)))
                   | map(select(.hooks != [])))
      | with_entries(select(.value != []))) as $h
  | [$h | prompts] as $live
  | {
      hooks: ($h | with_entries(.key as $e | .value |= map(.matcher as $m | .hooks |= map(
        if .type == "prompt" and $refs[pkey($e; $m)] then .prompt = "@" + $refs[pkey($e; $m)]
        else . end)))),
      files: ([$live[] | select($refs[.k]) | {($refs[.k]): .p}] | add // {}),
      stale: ([$refs[]] - [$live[] | $refs[.k] // empty]),
      unmapped: [$live[] | select($refs[.k] | not) | .k]
    }
' "$CLAUDE/settings.json" > "$out"

jq '.hooks' "$out" > "$REPO/hooks.json"
jq -r '.stale[]' "$out" | while IFS= read -r f; do
  rm -f "$REPO/$f"; rmdir "$(dirname "$REPO/$f")" 2>/dev/null || true
done
jq -r '.files | keys[]' "$out" | while IFS= read -r f; do
  mkdir -p "$(dirname "$REPO/$f")"
  jq -r --arg f "$f" '.files[$f]' "$out" > "$REPO/$f"
done
jq -r '.unmapped[] | "warning: prompt hook \(.) left inline in hooks.json. To give it a file, save its text as hooks/<name>/prompt.md and set its prompt to \"@hooks/<name>/prompt.md\"."' \
  "$out" >&2

echo "dumped to $REPO"
