#!/bin/bash

APP_NAME="safeeyes"

printf "Installing $APP_NAME"

sudo add-apt-repository -y ppa:slgobinath/safeeyes
sudo apt update
sudo apt install -y safeeyes

printf "\n$APP_NAME successfully installed\n"
