#!/bin/bash

BASE_DIR=$(dirname "$0")

DOTFILES_DIR=$(realpath "$BASE_DIR"/../dotfiles)

USER_BASHRC_DIR="$HOME"/.bashrc.d

printf "Linking dotfiles from $DOTFILES_DIR to $USER_BASHRC_DIR\n"

# Link directories
ln -sT "$DOTFILES_DIR" "$USER_BASHRC_DIR"

printf "Dotfiles successfully linked\n"