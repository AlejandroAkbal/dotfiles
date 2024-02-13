@echo off

rem Get admin

echo This will first install chocolatey, then other tools
echo .
echo Browse https://chocolatey.org/packages for packages
echo .
echo Ensure that your cmd.exe runs as Administrator
echo .

@"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -InputFormat None -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"

pause

echo Now chocolatey should be ready and we can go ahead
echo .
pause

call refreshenv

:START

choco feature enable -n=allowGlobalConfirmation
choco feature enable -n=useRememberedArgumentsForUpgrades

choco install choco-upgrade-all-at --params "'/DAILY:yes /TIME:10:00 /ABORTTIME:14:00'"

rem Browser related
choco install firefox
choco install googlechrome

rem Game related
choco install steam
@REM choco install goggalaxy
@REM choco install itch
@REM choco install nvidia-geforce-now
choco install vortex
@REM choco install minecraft-launcher --params "'/NOICON'"

rem Communication related
@REM choco install discord

rem Software Development related
choco install powershell-core --install-arguments="'DISABLE_TELEMETRY'" --packageparameters '"/CleanUpPath"'
choco install git --params "/NoAutoCrlf"

choco install github-desktop

choco install vscode --params "/NoDesktopIcon /NoQuicklaunchIcon /NoContextMenuFiles /NoContextMenuFolders"
choco install jetbrainstoolbox
@REM choco install notepadplusplus

@REM choco install docker-desktop
choco install podman-desktop

@REM choco install figma

choco install termius
@REM choco install postman
@REM choco install dbeaver

rem Development fonts
@REM choco install jetbrainsmono
@REM choco install firacode

rem Security related
choco install authy-desktop

rem Media related
choco install obs-studio 
@REM choco install spotify
choco install vlc

rem Utilities
choco install powertoys
@REM choco install openhardwaremonitor 

@REM choco install vnc-viewer
@REM choco install vnc-connect

choco install bulk-crap-uninstaller
choco install everything
choco install wiztree
choco install rufus
@REM choco install fastcopy
@REM choco install eraser

choco install jdownloader

@REM choco install virtualbox

choco install qbittorrent

rem Office and work related
@REM choco install gimp
@REM choco install libreoffice-fresh

choco install stretchly

rem Libraries related
choco install nvm
choco install python3
choco install openjdk 

rem Windows OS related
choco install sophiapp
choco install auto-dark-mode

choco install adb

choco install nvidia-display-driver

call refreshenv
:END

echo To keep your system updated, run choco upgrade all periodically
echo .
pause