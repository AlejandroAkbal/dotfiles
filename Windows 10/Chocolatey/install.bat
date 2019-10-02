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

rem Browser related
choco install firefox
choco install firefox-dev --pre
choco install tor-browser
choco install googlechrome
call refreshenv

rem Game related
choco install steam
choco install goggalaxy
choco install epicgameslauncher
choco install vortex
choco install minecraft
call refreshenv

rem Communication related
choco install discord
call refreshenv

rem Software Development related
choco install nodejs
choco install git
choco install github-desktop
choco install notepadplusplus
choco install vscode
choco install mobaxterm
call refreshenv

rem Miscelania
choco install chocolateygui
choco install obs-studio 
choco install qbittorrent
choco install 7zip
choco install f.lux
call refreshenv

rem Media related
choco install spotify 
choco install vlc
call refreshenv

rem Utilities
choco install bulk-crap-uninstaller
choco install vnc-viewer
choco install vnc-connect
choco install wiztree
choco install rufus
choco install virtualbox
choco install openhardwaremonitor 
choco install fastcopy
call refreshenv

rem Office and work related
choco install libreoffice-fresh 
call refreshenv

rem Libraries related
choco install jdk8 
call refreshenv

:END

echo To keep your system updated, run update-all.bat regularly from an administrator CMD.exe.
echo .
pause