# Load VCS info
autoload -Uz vcs_info
precmd() { vcs_info }

# Prompt configuration
zstyle ':vcs_info:git:*' formats '%b '
setopt PROMPT_SUBST
PROMPT='%F{green}%*%f %F{blue}%~%f %F{red}${vcs_info_msg_0_}%f$ '
