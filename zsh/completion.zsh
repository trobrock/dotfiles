zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "~/.zsh/compcache"
zstyle ':completion:*' menu select

fpath=(~/.zsh/completions $fpath)
autoload -U compinit
compinit
