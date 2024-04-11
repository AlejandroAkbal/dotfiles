#!/bin/bash

APP_NAME="poetry"

printf "Installing $APP_NAME"

curl -sSL https://install.python-poetry.org | python3 -

printf "\n$APP_NAME successfully installed\n"
