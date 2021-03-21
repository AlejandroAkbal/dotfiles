#!/bin/bash

APP_NAME="Docker"

printf "Installing $APP_NAME"

sudo apt install -y docker.io

# Enable services
sudo systemctl enable --now docker

# Add `docker` group to current user
sudo usermod -aG docker $USER

sudo apt install -y docker-compose

sudo docker run hello-world

printf "\n$APP_NAME successfully installed\n"
