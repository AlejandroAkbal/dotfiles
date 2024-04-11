#!/bin/bash

APP_NAME="PhpStorm fix for GitHub Desktop"

printf "Installing $APP_NAME"

cd .local/share/JetBrains/Toolbox/scripts

ln -s ./PhpStorm phpstorm

printf "\n$APP_NAME successfully installed\n"
