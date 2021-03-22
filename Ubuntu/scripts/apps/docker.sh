#!/bin/bash

APP_NAME="Docker"

printf "Installing $APP_NAME"

# Docker

sudo apt update

sudo apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
    "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt update

sudo apt install -y docker-ce docker-ce-cli containerd.io

# Docker compose

sudo curl -L "https://github.com/docker/compose/releases/download/1.28.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

# Configuration

sudo systemctl enable docker.service
sudo systemctl enable containerd.service

sudo groupadd docker

sudo usermod -aG docker $USER

newgrp docker

# Test
docker run hello-world

printf "\n$APP_NAME successfully installed\n"
