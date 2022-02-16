#!/bin/bash

APP_NAME="Docker"

printf "Installing $APP_NAME"

# Docker
# https://docs.docker.com/engine/install/ubuntu/#install-using-the-convenience-script

curl -fsSL https://get.docker.com -o get-docker.sh

sudo sh get-docker.sh

rm get-docker.sh

dockerd-rootless-setuptool.sh install --force

# Docker compose
# https://docs.docker.com/compose/install

sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

# Test
docker run hello-world

printf "\n$APP_NAME successfully installed\n"
