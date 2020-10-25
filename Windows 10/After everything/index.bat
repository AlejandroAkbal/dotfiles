@echo off

echo Configuring git to have lf endings
git config --global core.autocrlf false
git config --global core.eol lf


echo Configuring windows to autostart ssh-agent
Set-Service ssh-agent -StartupType Automatic

echo Done