#!/bin/bash

APP_NAME="VeraCrypt"

printf "Installing $APP_NAME"

curl -L "https://launchpad.net/veracrypt/trunk/1.25.9/+download/veracrypt-1.25.9-Ubuntu-20.04-amd64.deb" -o ./veracrypt.deb

sudo apt install -y ./veracrypt.deb

rm ./veracrypt.deb

printf "\n$APP_NAME successfully installed\n"
