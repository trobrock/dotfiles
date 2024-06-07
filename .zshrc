source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/prompt.zsh
source ~/.zsh/history.zsh
source ~/.zsh/completion.zsh
source ~/.zsh/aliases.zsh

eval "$(direnv hook zsh)"
eval "$(rbenv init - zsh)"

alias vim="nvim"
export EDITOR="nvim"
export PATH="./bin:$PATH"
