source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/prompt.zsh
source ~/.zsh/history.zsh
source ~/.zsh/completion.zsh
source ~/.zsh/aliases.zsh

export EDITOR="$HOME/code_wait"
export PATH="./bin:$PATH"

eval "$(direnv hook zsh)"
# eval "$(rbenv init - zsh)"
