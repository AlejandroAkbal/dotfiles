#!/bin/bash

APP_NAME="Jetbrains Toolbox"

# https://github.com/nagygergo/jetbrains-toolbox-install
printf "Installing $APP_NAME"

sudo apt install -y libfuse2 libxi6 libxrender1 libxtst6 mesa-utils libfontconfig libgtk-3-bin tar

curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/master/jetbrains-toolbox.sh | bash

printf "\n$APP_NAME successfully installed\n"
