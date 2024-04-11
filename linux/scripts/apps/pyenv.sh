#!/bin/bash

APP_NAME="pyenv"

printf "Installing $APP_NAME"


curl https://pyenv.run | bash


# https://github.com/pyenv/pyenv/wiki#suggested-build-environment
sudo apt update; sudo apt install -y build-essential libssl-dev zlib1g-dev \
libbz2-dev libreadline-dev libsqlite3-dev curl \
libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

printf "\n$APP_NAME successfully installed\n"
