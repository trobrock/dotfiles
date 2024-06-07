alias reload='exec $SHELL -l'

alias vim="nvim"

alias ls='eza'
alias ll='eza -lah'
alias lt='eza -lah -I .git --tree'

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
alias gm='git merge --no-ff'
alias gmff='git merge'
alias gmff='git merge'
alias gp='git push'
alias gpq='git pull-request'
alias gpu='git push -u origin $(git rev-parse --abbrev-ref HEAD)'
alias gss='git status -s'

alias clean='find ./**/*.orig | xargs rm'

alias b='bundle install'
alias ip='curl http://ipv4.icanhazip.com'
alias cov="open coverage/index.html"

alias update='brew update && brew upgrade'

alias t='bin/rails test'
alias ts='bin/rails test:system'
alias ta='bin/rails test && bin/rails test:system'

function gbisect() {
  good=$1
  bad=${2:-"HEAD"}
  git bisect start ;
  git bisect bad $bad ;
  git bisect good $good ;
  git bisect run ~/git-bisect.sh ;
}

function c() {
  cd ~/Sites/$1
}
