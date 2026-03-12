alias reload='exec $SHELL -l'
alias ip='curl http://ipv4.icanhazip.com'

# vim
alias vim="nvim"

# ls
alias ls='eza'
alias ll='eza -lah'
alias lt='eza -lah -I .git --tree'

# cat
alias cat='bat'

# git
alias lg='lazygit'
alias gaa='git add -A'
alias gb='git branch'
alias gbc='git branch --merged | grep -v main | xargs git branch -d'
alias gc='git commit'
alias gco='git checkout'
alias gd='git diff'
alias gdc='git diff --cached'
alias gf='git fetch -p'
alias gl='git pull'
alias gld='git pull && gbc'
alias glm='git pull origin main'
alias gm='git merge --no-ff'
alias gmff='git merge'
alias gp='git push'
alias gpq='gh pr create'
alias gpu='git push -u origin $(git rev-parse --abbrev-ref HEAD)'
alias gss='git status -s'
alias clean='find ./**/*.orig | xargs rm'

function gbisect() {
  good=$1
  bad=${2:-"HEAD"}
  git bisect start ;
  git bisect bad $bad ;
  git bisect good $good ;
  git bisect run ~/git-bisect.sh ;
}

# rails
alias b='bundle install'
alias t='bin/rails test'
alias ts='bin/rails test:system'
alias ta='bin/rails test && bin/rails test:system'

# tmux
function tm() {
  if ! tmux has-session 2>/dev/null; then
    tmux new-session -d -s "dev"
    tmux new-session -d -s "dotfiles"
    tmux send-keys -t "dotfiles" "cd dotfiles" C-m
    tmux send-keys -t "dotfiles" C-l
  fi

  tmux attach-session -t "dev"
}

# AI
alias crush='crush --yolo'

# Find packages without leaving the terminal
alias yayf="yay -Slq | fzf --multi --preview 'yay -Sii {1}' --preview-window=down:75% | xargs -ro yay -S"

# web apps
function web2app() {
  if [ "$#" -ne 3 ]; then
    echo "Usage: web2app <AppName> <AppURL> <IconURL> (IconURL must be in PNG -- use https://dashboardicons.com)"
    return 1
  fi

  local APP_NAME="$1"
  local APP_URL="$2"
  local ICON_URL="$3"
  local ICON_DIR="$HOME/.local/share/applications/icons"
  local DESKTOP_FILE="$HOME/.local/share/applications/${APP_NAME}.desktop"
  local ICON_PATH="${ICON_DIR}/${APP_NAME}.png"

  mkdir -p "$ICON_DIR"

  if ! curl -sL -o "$ICON_PATH" "$ICON_URL"; then
    echo "Error: Failed to download icon."
    return 1
  fi

  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Version=1.0
Name=$APP_NAME
Comment=$APP_NAME
Exec=chromium --new-window --ozone-platform=wayland --app="$APP_URL" --name="$APP_NAME" --class="$APP_NAME"
Terminal=false
Type=Application
Icon=$ICON_PATH
StartupNotify=true
EOF

  chmod +x "$DESKTOP_FILE"
}

function web2app-remove() {
  if [ "$#" -ne 1 ]; then
    echo "Usage: web2app-remove <AppName>"
    return 1
  fi

  local APP_NAME="$1"
  local ICON_DIR="$HOME/.local/share/applications/icons"
  local DESKTOP_FILE="$HOME/.local/share/applications/${APP_NAME}.desktop"
  local ICON_PATH="${ICON_DIR}/${APP_NAME}.png"

  rm "$DESKTOP_FILE"
  rm "$ICON_PATH"
}

# worktrunk
# wtc [--plan] [--tmux [--name <win>]] [-f <file>] <branch_name> [prompt]
function wtc() {
  local use_plan=false
  local use_tmux=false
  local win_name=""
  local prompt_file=""
  local args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan)  use_plan=true; shift ;;
      --tmux)  use_tmux=true; shift ;;
      --name)  win_name="$2"; shift 2 ;;
      -f)      prompt_file="$2"; shift 2 ;;
      *)       args+=("$1"); shift ;;
    esac
  done

  local branch_name="${args[1]}"
  if [ -z "$branch_name" ]; then
    echo "Usage: wtc [--plan] [--tmux [--name <win>]] [-f <file>] <branch> [prompt]"
    return 1
  fi

  # Resolve prompt: positional arg > -f file > stdin
  local prompt="${args[2]}"
  if [ -z "$prompt" ] && [ -n "$prompt_file" ]; then
    prompt=$(<"$prompt_file")
  elif [ -z "$prompt" ] && [ ! -t 0 ]; then
    prompt=$(cat)
  fi

  # Branch existence check
  local is_pr=false
  local create_flag=""
  if [[ "$branch_name" =~ ^pr:([0-9]+)$ ]]; then
    is_pr=true
  fi
  if [ "$is_pr" = false ]; then
    local branch_exists=$(git branch --list "$branch_name" || \
      git ls-remote --heads origin "$branch_name")
    if [ -z "$branch_exists" ]; then
      create_flag="--create"
    fi
  fi

  local agent_flag=()
  if [ "$use_plan" = true ]; then
    agent_flag=(--agent plan)
  fi

  if [ "$use_tmux" = true ]; then
    # --- tmux mode: spawn in a detached window ---
    if [ -z "$win_name" ]; then
      win_name="${branch_name##*-}"
    fi

    local tmpfile=$(mktemp /tmp/wtc-XXXXXX.txt)
    printf '%s' "$prompt" > "$tmpfile"

    tmux new-window -dn "$win_name"

    local prompt_arg=""
    if [ -n "$prompt" ]; then
      prompt_arg="--prompt \"\$PROMPT\""
    fi

    tmux send-keys -t ":$win_name" \
      "PROMPT=\$(cat $tmpfile) && rm $tmpfile && wt switch $create_flag \"$branch_name\" -x opencode -- ${agent_flag[*]} $prompt_arg" Enter

    echo "Spawned in tmux window '$win_name' on branch '$branch_name'"
    echo "Connect: tmux select-window -t \":$win_name\""
  else
    # --- normal mode: run in current shell ---
    if [ -n "$prompt" ]; then
      wt switch $create_flag "$branch_name" -x opencode -- "${agent_flag[@]}" --prompt "$prompt"
    else
      wt switch $create_flag "$branch_name" -x opencode -- "${agent_flag[@]}"
    fi
  fi
}
# wtm - merge current branch, delete it, pull latest changes
function wtm() {
   gh pr merge --admin &&
     wt remove -D &&
     git pull
}

alias wtd='wt remove -D'

# tunnel - create an SSH local port forward
# Usage: tunnel localhost:1234 trobrock-home:1234
function tunnel() {
  if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: tunnel <local_host>:<local_port> <remote_host>:<remote_port>"
    return 1
  fi

  local local_part="$1"
  local remote_part="$2"

  local local_host="${local_part%%:*}"
  local local_port="${local_part##*:}"
  local remote_host="${remote_part%%:*}"
  local remote_port="${remote_part##*:}"

  echo "Tunneling ${local_host}:${local_port} -> ${remote_host}:${remote_port}"
  ssh -f -N -L "${local_port}:localhost:${remote_port}" "${remote_host}"
  echo "Tunnel established (PID: $(pgrep -f "ssh.*-L.*${local_port}.*${remote_host}" | tail -1))"
}
