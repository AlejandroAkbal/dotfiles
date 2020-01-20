#!/bin/bash

# Install dependencies
sudo apt update
sudo apt install nodejs npm python3-pip git gdebi-core

# Install apps
sudo snap install --classic code

# Google Chrome
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
sudo gdebi google-chrome-stable_current_amd64.deb
rm google-chrome-stable_current_amd64.deb

# Set python
sudo update-alternatives --install /usr/bin/python python /usr/bin/python3 10
sudo update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 10
