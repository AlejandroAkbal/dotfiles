@echo off

echo Configuring git to have lf endings
git config --global core.autocrlf false
git config --global core.eol lf


echo Configuring windows to autostart ssh-agent
Set-Service ssh-agent -StartupType Automatic

echo Symlinking LibreWolf overrides

@REM Create the directory if it doesn't exist
cmd /c if not exist "%USERPROFILE%\.librewolf" mkdir "%USERPROFILE%\.librewolf"

@REM Create the symlink
cmd /c mklink "%USERPROFILE%\.librewolf\librewolf.overrides.cfg" "..\..\shared\dotfiles\librewolf.overrides.cfg"

echo Done
pause