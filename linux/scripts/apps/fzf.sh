
#!/bin/bash

APP_NAME="FZF"

printf "Installing $APP_NAME"

git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

printf "\n$APP_NAME successfully installed\n"