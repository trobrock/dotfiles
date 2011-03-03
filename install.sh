#!/bin/bash
git clone git://github.com/trobrock/dotfiles ~/.dotfiles
cd ~/.dotfiles
git submodule update --init
rake install
