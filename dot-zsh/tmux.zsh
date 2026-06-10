# Keep SSH agent forwarding usable inside long-lived tmux panes.
#
# tmux updates its session environment from the client on attach, but already
# running shells do not receive that changed environment. Refresh SSH_AUTH_SOCK
# from tmux at each prompt so git SSH signing follows the current forwarded
# agent after reconnecting from a different machine.
_tmux_refresh_ssh_auth_sock() {
  [[ -n ${TMUX:-} ]] || return
  (( $+commands[tmux] )) || return

  local tmux_env tmux_sock
  tmux_env=$(tmux show-environment SSH_AUTH_SOCK 2>/dev/null) || return

  if [[ $tmux_env == SSH_AUTH_SOCK=* ]]; then
    tmux_sock=${tmux_env#SSH_AUTH_SOCK=}
    if [[ -n $tmux_sock && ${SSH_AUTH_SOCK:-} != $tmux_sock ]]; then
      export SSH_AUTH_SOCK=$tmux_sock
    fi
  elif [[ $tmux_env == -SSH_AUTH_SOCK ]]; then
    unset SSH_AUTH_SOCK
  fi
}

if [[ -n ${TMUX:-} ]]; then
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd _tmux_refresh_ssh_auth_sock
  _tmux_refresh_ssh_auth_sock
fi
