alias reload='exec $SHELL -l'
alias update='brew update && brew upgrade'
alias ip='curl http://ipv4.icanhazip.com'

# vim
alias vim="nvim"

# ls
alias ls='eza'
alias ll='eza -lah'
alias lt='eza -lah -I .git --tree'

# cat
alias cat='bat'

# ssh
alias ssh='kitten ssh'

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
