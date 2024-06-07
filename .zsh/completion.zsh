zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "~/.zsh/compcache"
zstyle ':completion:*' menu select

# fuzzy matching
zstyle ':completion:*' matcher-list 'm:{[:lower:][:upper:]}={[:upper:][:lower:]}' 'r:|=*' 'l:|=* r:|=*'

fpath=(~/.zsh/completions $fpath)
autoload -U compinit
compinit
