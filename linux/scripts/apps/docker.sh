#!/bin/bash

APP_NAME="Docker"

printf "Installing $APP_NAME"

# Docker
# https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script

curl -fsSL https://get.docker.com -o get-docker.sh

sudo sh get-docker.sh

rm get-docker.sh

# Post-installation steps for Linux
# https://docs.docker.com/engine/install/linux-postinstall/

sudo usermod -aG docker $USER

# Test
docker run hello-world

printf "\n$APP_NAME successfully installed\n"
