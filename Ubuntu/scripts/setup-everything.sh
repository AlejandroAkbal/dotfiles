#!/bin/bash

bash copy_dotfiles.sh

# Install dependencies
sudo apt update && sudo apt full-upgrade -y

function install() {
    which $1 &>/dev/null

    if [ $? -ne 0 ]; then
        echo "Installing: ${1}..."
        sudo apt install -y $1
    else
        echo "Already installed: ${1}"
    fi
}

function install_snap() {
    which $1 &>/dev/null

    if [ $? -ne 0 ]; then
        echo "Installing snap: ${1}..."
        sudo snap install $1
    else
        echo "Already installed snap: ${1}"
    fi
}

# Basics
install_snap "spotify"

install_snap "--beta authy"

# Browsers
install_snap "chromium"

# Communication
install_snap "discord"

# Games
install "steam"

# Media
install "vlc"

install "gimp"

install "obs-studio"

# Editors
install_snap "--classic code"
install_snap "--classic phpstorm"

# Design
install_snap "figma-linux"

# Utils
install "git"

install_snap "postman"
install_snap "dbeaver-ce"

install "unzip"

install "gdebi-core"

# Languages
install "python3-venv"
install "python3-pip"

# Fonts
install "fonts-firacode"

# Run all scripts in directory
for f in apps/*.sh; do
    bash "$f" || break
done
