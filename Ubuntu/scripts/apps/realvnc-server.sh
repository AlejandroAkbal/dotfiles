#!/bin/bash

APP_NAME="realvnc-server"

printf "Installing $APP_NAME"

cd /tmp

wget https://www.realvnc.com/download/file/vnc.files/VNC-Server-6.7.2-Linux-x86.deb

sudo apt install -y ./VNC-Server-6.7.2-Linux-x86.deb

rm VNC-Server-6.7.2-Linux-x86.deb

printf "\n$APP_NAME successfully installed\n"
