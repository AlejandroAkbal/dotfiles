#!/bin/bash

BASEDIR=$(pwd)

DOTFILES_DIR="$BASEDIR"/../dotfiles

for file in "$DOTFILES_DIR"/.*;
do
  ln -s "$file" "$HOME"
done