# Intentionally do not refresh SSH_AUTH_SOCK from tmux.
#
# Git signing uses the fixed local agent at ~/.ssh/agent.sock (via ~/.zshenv and
# ~/.config/scripts/git-ssh-sign). Pulling SSH_AUTH_SOCK from tmux can reintroduce
# stale /run/user/... sockets into long-lived panes and break signed commits.
#
# If a one-off workflow needs a forwarded agent, export SSH_AUTH_SOCK manually in
# that pane for that workflow.
