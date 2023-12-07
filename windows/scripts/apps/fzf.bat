
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "This script requires PowerShell 7 or higher."
    exit
}

choco install fzf

Install-Module -Name PSFzf

@REM TODO: Link ../config/Microsoft.PowerShell_profile.ps1 to $PROFILE