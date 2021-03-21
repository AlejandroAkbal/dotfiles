#!/bin/bash

APP_NAME="realvnc-viewer"

printf "Installing $APP_NAME"

cd /tmp

wget https://www.realvnc.com/download/file/viewer.files/VNC-Viewer-6.20.529-Linux-x86.deb

sudo apt install -y ./VNC-Viewer-6.20.529-Linux-x86.deb

rm VNC-Viewer-6.20.529-Linux-x86.deb

printf "\n$APP_NAME successfully installed\n"
