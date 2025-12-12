alias reload='exec $SHELL -l'
alias ip='curl http://ipv4.icanhazip.com'

# worktree
alias wt='worktree'

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
