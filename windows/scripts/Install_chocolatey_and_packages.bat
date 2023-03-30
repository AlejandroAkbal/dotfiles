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
choco install librewolf
choco install googlechrome

rem Game related
choco install steam
@REM choco install goggalaxy
choco install itch
@REM choco install nvidia-geforce-now
choco install vortex
@REM choco install minecraft-launcher --params "'/NOICON'"

rem Communication related
choco install discord

rem Software Development related
choco install powershell-core --install-arguments="'ADD_FILE_CONTEXT_MENU_RUNPOWERSHELL=1 ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1 ADD_EXPLORER_CONTEXT_MENU_OPENPOWERSHELL=1'" --packageparameters '"/CleanUpPath"' 
choco install git --params "/NoAutoCrlf"
choco install github-desktop

choco install vscode --params "/NoDesktopIcon /NoQuicklaunchIcon /NoContextMenuFiles /NoContextMenuFolders"
@REM choco install notepadplusplus

choco install docker-desktop

@REM choco install figma

@REM choco install mobaxterm
@REM choco install postman
@REM choco install dbeaver

rem Development fonts
@REM choco install jetbrainsmono
@REM choco install firacode

rem Security related
choco install authy-desktop

rem Media related
choco install obs-studio 
choco install spotify 
choco install vlc

@REM choco install equalizerapo

rem Utilities
choco install 7zip
choco install google-backup-and-sync

choco install powertoys

@REM choco install f.lux
@REM choco install click-monitor-ddc
@REM choco install openhardwaremonitor 

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

choco install workrave

rem Libraries related
choco install nvm
choco install python3
choco install openjdk 

rem Windows OS related
choco install sophiapp

call refreshenv
:END

echo To keep your system updated, run choco upgrade all periodically
echo .
pause