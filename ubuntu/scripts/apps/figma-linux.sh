#!/bin/bash

printf "Making necessary changes for Figma to work correctly"

sudo ln -s $HOME/.local/share/fonts $HOME/snap/figma-linux/current/.local/share/

printf "Done making changes"
