#!/bin/bash

APP_NAME="Firefox Developer Edition"

printf "Installing $APP_NAME"

cd "$HOME/Downloads"

curl -L "https://download.mozilla.org/?product=firefox-devedition-latest-ssl&os=linux64&lang=en-US" -o firefox-dev.tar.bz2

tar -xvf firefox-dev.tar.bz2

sudo mv firefox /opt/firefox-dev

sudo chown -R "$USER" /opt/firefox-dev

sudo ln -s /opt/firefox-dev/firefox /usr/local/bin/firefox-dev

echo \
"[Desktop Entry]
Encoding=UTF-8
Name=Firefox Developer
GenericName=Firefox Developer Edition
Exec=/usr/local/bin/firefox-dev %u
Terminal=false
Icon=/opt/firefox-dev/browser/chrome/icons/default/default128.png
Type=Application
Categories=Application;Network;WebBrowser;X-Developer;
Comment=Firefox Developer Edition Web Browser
StartupWMClass=firefox-aurora" \
      | sudo tee /usr/share/applications/firefox-developer.desktop  > /dev/null

rm firefox-dev.tar.bz2

printf "\n$APP_NAME successfully installed\n"
