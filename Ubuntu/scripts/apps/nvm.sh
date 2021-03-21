#!/bin/bash

APP_NAME="nvm"

printf "Installing $APP_NAME"

cd /tmp

curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.37.2/install.sh | bash

source ~/.bashrc

nvm install node
nvm install-latest-npm

printf "\n$APP_NAME successfully installed\n"
