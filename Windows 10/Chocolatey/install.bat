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

choco feature enable -n=allowGlobalConfirmation
choco feature enable -n=useRememberedArgumentsForUpgrades

rem Browser related
choco install firefox-dev
choco install googlechrome

rem Game related
choco install steam
choco install goggalaxy
choco install nvidia-geforce-now
choco install vortex
choco install minecraft-launcher --params "'/NOICON'"

rem Communication related
choco install discord

rem Software Development related
choco install powershell-core --install-arguments="'ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1'" --packageparameters '"/CleanUpPath"' 
choco install git --params "/NoAutoCrlf"
choco install github-desktop

choco install vscode --params "/NoDesktopIcon /NoQuicklaunchIcon /NoContextMenuFiles /NoContextMenuFolders"
choco install notepadplusplus

choco install figma

choco install mobaxterm
choco install insomnia-rest-api-client
choco install dbeaver

rem Development fonts
choco install jetbrainsmono
choco install firacode

rem Security related
choco install authy-desktop

rem Media related
choco install obs-studio 
choco install spotify 
choco install vlc

choco install equalizerapo

rem Utilities
choco install 7zip

choco install powertoys

choco install f.lux

choco install click-monitor-ddc
choco install openhardwaremonitor 

choco install vnc-viewer
choco install vnc-connect

choco install bulk-crap-uninstaller
choco install everything
choco install wiztree
choco install rufus
choco install fastcopy
choco install eraser

choco install jdownloader

choco install virtualbox

choco install deluge

rem Office and work related
choco install gimp
choco install libreoffice-fresh 

rem Libraries related
choco install nvm
choco install python3
choco install openjdk 
call refreshenv

:END

echo To keep your system updated, run choco upgrade all periodically
echo .
pause