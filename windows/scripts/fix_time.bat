@echo off
(NET FILE||(PowerShell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%0' -Verb RunAs")&(NET FILE||exit)) >nul 2>&1

net stop w32time
w32tm /unregister
w32tm /register
REG ADD "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" /v "SpecialPollInterval" /t REG_DWORD /d "86400" /f
sc triggerinfo w32time start/networkon stop/networkoff
net start w32time
w32tm /config /manualpeerlist:"0.pool.ntp.org,0x1 1.pool.ntp.org,0x1 2.pool.ntp.org,0x1 3.pool.ntp.org,0x1" /syncfromflags:manual /update
w32tm /resync /force

pause