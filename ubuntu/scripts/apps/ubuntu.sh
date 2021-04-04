#!/bin/bash

printf "Making Ubuntu changes"

sudo systemctl disable cups --now
sudo systemctl disable cups-browsed --now

printf "Done making changes"
