@echo off

rem Get admin
set "params=%*"
cd /d "%~dp0" && ( if exist "%temp%\getadmin.vbs" del "%temp%\getadmin.vbs" ) && fsutil dirty query %systemdrive% 1>nul 2>nul || (  echo Set UAC = CreateObject^("Shell.Application"^) : UAC.ShellExecute "cmd.exe", "/k cd ""%~sdp0"" && %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs" && "%temp%\getadmin.vbs" && exit /B )

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

rem Game related
choco install steam
choco install goggalaxy
choco install epicgameslauncher
choco install vortex
choco install minecraft

rem Communication related
choco install discord

rem Software Development related
choco install nodejs
choco install github-desktop
choco install notepadplusplus
choco install vscode
choco install mobaxterm

rem Miscelania
choco install obs-studio 
choco install qbittorrent
choco install 7zip
choco install f.lux

rem Media related
choco install spotify 
choco install vlc

rem Utilities
choco install bulk-crap-uninstaller
choco install vnc-viewer
choco install vnc-connect
choco install wiztree
choco install rufus
choco install virtualbox
choco install openhardwaremonitor 

rem Office and work related
choco install libreoffice-fresh 

rem Libraries related
choco install jdk8 

:END

echo To keep your system updated, run update-all.bat regularly from an administrator CMD.exe.
echo .
pause