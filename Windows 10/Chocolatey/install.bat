@echo off

rem Get admin

echo This will first install chocolatey, then other tools
echo .
echo Browse https://chocolatey.org/packages for packages
echo .
echo Ensure that your cmd.exe runs as Administrator
echo .

@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"

choco feature enable -n=allowGlobalConfirmation
pause

echo Now chocolatey should be ready and we can go ahead
echo .
pause

call refreshenv

:START

choco feature enable -n allowGlobalConfirmation

rem Browser related
choco install firefox-dev --pre
choco install googlechrome

rem Game related
choco install steam
choco install vortex
choco install minecraft

rem Communication related
choco install discord

rem Software Development related
choco install git
choco install github-desktop

choco install vscode
choco install visualstudio2019community 
choco install notepadplusplus

choco install mobaxterm
choco install postman
choco install dbeaver

rem Media related
choco install obs-studio 
choco install spotify 
choco install vlc

rem Utilities
choco install 7zip

choco install f.lux
choco install click-monitor-ddc

choco install vnc-viewer
choco install vnc-connect

choco install bulk-crap-uninstaller
choco install wiztree
choco install rufus
choco install fastcopy

choco install virtualbox
choco install openhardwaremonitor 

choco install deluge
choco install chocolateygui

rem Office and work related
choco install libreoffice-fresh 

rem Libraries related
choco install nodejs
choco install python3
choco install jdk8 
call refreshenv

:END

echo To keep your system updated, run choco upgrade all periodically
echo .
pause