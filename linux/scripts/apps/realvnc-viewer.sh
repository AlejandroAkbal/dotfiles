#!/bin/bash

APP_NAME="realvnc-viewer"

printf "Installing $APP_NAME"

cd /tmp

wget https://www.realvnc.com/download/file/viewer.files/VNC-Viewer-6.20.529-Linux-x86.deb -O VNC-Viewer.deb

sudo apt install -y ./VNC-Viewer.deb

rm VNC-Viewer.deb

printf "\n$APP_NAME successfully installed\n"
