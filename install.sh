#!/usr/bin/env bash

set -e

STRIPE_CLI_VERSION="1.19.2"

function log() {
  echo "[install dotfiles] $1"
}

function link() {
  rm -rf $HOME/.$1
  ln -s $PWD/$1 $HOME/.$1
  echo -e "\tLinked $1."
}

function mkd() {
  if [ ! -d "$1" ]; then
    mkdir -p $1
  fi
}

# Setup exe directories
log "Setting up executable directories"
mkdir ~/usr
mkdir ~/bin

# Install Stripe CLI
log "Installing Stripe CLI"
pushd ~/bin > /dev/null
echo -e "\tDownloading https://github.com/stripe/stripe-cli/releases/download/v$STRIPE_CLI_VERSION/stripe_${STRIPE_CLI_VERSION}_linux_x86_64.tar.gz"
curl -L --silent "https://github.com/stripe/stripe-cli/releases/download/v$STRIPE_CLI_VERSION/stripe_${STRIPE_CLI_VERSION}_linux_x86_64.tar.gz" | tar xzv
popd > /dev/null
mkd $HOME/.config/stripe
if [ -d /workspaces/.codespaces ]; then
  mkd /workspaces/.codespaces/.persistedshare/stripe
  ln -s /workspaces/.codespaces/.persistedshare/stripe/config.toml $HOME/.config/stripe/config.toml
fi

# Install diff-so-fancy
log "Installing diff-so-fancy"
git clone https://github.com/so-fancy/diff-so-fancy.git ~/usr/diff-so-fancy
ln -s ~/usr/diff-so-fancy/diff-so-fancy ~/bin/diff-so-fancy

# Link dotfiles and directories
log "Linking dotfiles and directories"
link zsh
link zshrc
link gitconfig
link gitignore
link irbrc

# Install ZSH Syntax Highlighting
log "Installing ZSH Syntax Highlighting"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.zsh/zsh-syntax-highlighting

log "Done"
