#!/bin/bash

APP_NAME="Jetbrains Toolbox"

printf "Installing $APP_NAME"

cd /tmp

wget https://download-cdn.jetbrains.com/toolbox/jetbrains-toolbox-1.22.10970.tar.gz

tar -xvzf jetbrains-toolbox-1.22.10970.tar.gz

chmod +x jetbrains-toolbox-1.22.10970/jetbrains-toolbox

mv jetbrains-toolbox-1.22.10970/jetbrains-toolbox /usr/local/bin/jetbrains-toolbox

rmdir jetbrains-toolbox-1.22.10970

printf "\n$APP_NAME successfully installed\n"
