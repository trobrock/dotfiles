function wtc-popup() {
  local branch prompt tmpfile plan_flag="" suggestion=""
  local ollama_model="${WTC_OLLAMA_MODEL:-llama3.2:1b}"

  prompt=$(gum write \
    --placeholder "initial prompt for claude (ctrl-d to finish, empty to skip)" \
    --header "prompt:  enter submit · ctrl+j new line · ctrl+e editor" \
    --no-show-help \
    --header.foreground "#cba6f7" --header.bold \
    --cursor.foreground "#cba6f7" \
    --placeholder.foreground "#bac2de" \
    --base.foreground "#f5e0dc" \
    --end-of-buffer.foreground "#585b70" \
    --width 80 --height 10) || return 1

  if [[ -n "$prompt" ]] && command -v ollama >/dev/null 2>&1; then
    local meta_prompt="Generate a short git branch name in kebab-case (max 4 words, lowercase, hyphens only, no quotes, no explanation) for this task:

$prompt

Reply with ONLY the branch name."
    local suggest_file
    suggest_file=$(mktemp "${TMPDIR:-/tmp}/wtc-suggest.XXXXXX")
    OLLAMA_META_PROMPT="$meta_prompt" gum spin --spinner dot --title "suggesting branch name..." \
      --spinner.foreground "#cba6f7" --title.foreground "#f5e0dc" --title.bold -- \
      sh -c "ollama run '$ollama_model' \"\$OLLAMA_META_PROMPT\" > '$suggest_file' 2>/dev/null"
    suggestion=$(awk 'NF' "$suggest_file" | tail -n 1 \
      | tr -d '\r"'"'" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9/-]+/-/g; s/^-+//; s/-+$//')
    rm -f "$suggest_file"
  fi

  branch=$(gum input \
    --placeholder "branch name (e.g. fix-auth-bug)" \
    --prompt "branch: " \
    --prompt.foreground "#cba6f7" --prompt.bold \
    --cursor.foreground "#cba6f7" \
    --placeholder.foreground "#bac2de" \
    --text.foreground "#f5e0dc" \
    --value "$suggestion") || return 1
  [[ -z "$branch" ]] && { echo "aborted: no branch"; return 1; }

  if gum confirm "enable --plan mode?" --default=no \
    --prompt.foreground "#f5e0dc" --prompt.bold \
    --selected.foreground "#1e1e2e" --selected.background "#cba6f7" --selected.bold \
    --unselected.foreground "#bac2de"; then
    plan_flag="--plan"
  fi

  tmpfile=$(mktemp "${TMPDIR:-/tmp}/wtc-popup.XXXXXX")
  printf '%s' "$prompt" > "$tmpfile"

  wtc --tmux $plan_flag -f "$tmpfile" "$branch"
  rm -f "$tmpfile"
}
