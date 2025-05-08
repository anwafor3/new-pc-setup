<#
.SYNOPSIS
  New PC Setup 2.0 - Automate local user creation, network connection, application installs, and BitLocker disable during first boot.
.DESCRIPTION
  1. Creates a local Administrator account named Owner (no password).
  2. Imports and connects to the BestBuy-GeekSquad Wi-Fi network.
  3. Installs Google Chrome, Zoom, and Adobe Acrobat Reader via winget or Chocolatey.
  4. Disables BitLocker on C: drive.
  Designed to be invoked automatically at first boot (e.g., via "SetupComplete.cmd" or RunOnce).
.EXAMPLE
  Place this script in %SystemDrive%\Setup\Scripts and call from SetupComplete.cmd:
    powershell.exe -ExecutionPolicy Bypass -File %SystemDrive%\Setup\Scripts\setup2.ps1
#>

# Ensure running as Administrator
If (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "Script must be run as Administrator."
    Exit 1
}

# Strict error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Logging setup
$LogFile = "$PSScriptRoot\setup2.log"
Function Log { param([string]$Message) ; "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`t$Message" | Tee-Object -FilePath $LogFile -Append }
Log '=== Setup 2.0 started ==='

#--- 1) Create local user Owner (no password) ---
$Username = 'Owner'
if (-not (Get-LocalUser -Name $Username -ErrorAction SilentlyContinue)) {
    New-LocalUser -Name $Username -NoPassword -FullName $Username -Description 'Local administrator account'
    Add-LocalGroupMember -Group 'Administrators' -Member $Username
    Log "Local user '$Username' created and added to Administrators."
} else {
    Log "Local user '$Username' already exists."
}

#--- 2) Configure & connect Wi-Fi ---
$SSID = 'BestBuy-GeekSquad'
$Key  = 'Agents4ssembl32024!'
$WifiXml = @"
<?xml version=\"1.0\"?>
<WLANProfile xmlns=\"http://www.microsoft.com/networking/WLAN/profile/v1\">
  <name>$SSID</name>
  <SSIDConfig><SSID><name>$SSID</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>auto</connectionMode>
  <MSM><security>
    <authEncryption><authentication>WPA2PSK</authentication><encryption>AES</encryption><useOneX>false</useOneX></authEncryption>
    <sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>$Key</keyMaterial></sharedKey>
  </security></MSM>
</WLANProfile>
"@
$ProfilePath = "$PSScriptRoot\WifiProfile.xml"
$WifiXml | Out-File -FilePath $ProfilePath -Encoding ASCII
Log "Wi-Fi profile written to $ProfilePath."
netsh wlan add profile filename="$ProfilePath" user=all | Out-Null
netsh wlan connect name="$SSID" | Out-Null
Log "Attempted connection to SSID '$SSID'."

#--- 3) Install applications ---
$Apps = @(
    @{Name='Google Chrome';Id='Google.Chrome'},
    @{Name='Zoom';          Id='Zoom.Zoom'},
    @{Name='Adobe Reader';  Id='Adobe.Reader'}
)
$PkgMgr = if (Get-Command winget -ErrorAction SilentlyContinue) {'winget'} elseif (Get-Command choco -ErrorAction SilentlyContinue) {'choco'} else {
    Log 'Neither winget nor choco found; installing Chocolatey.'
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
    'choco'
}
Log "Using $PkgMgr for installs."
foreach ($app in $Apps) {
    Log "Installing $($app.Name)..."
    if ($PkgMgr -eq 'winget') { winget install --id=$($app.Id) -e --accept-package-agreements --accept-source-agreements } else { choco install $($app.Id) -y }
    if ($LASTEXITCODE -eq 0) { Log "$($app.Name) installed." } else { Log "Error installing $($app.Name) - code $LASTEXITCODE." }
}

#--- 4) Disable BitLocker ---
try {
    $bv = Get-BitLockerVolume -MountPoint 'C:'
    if ($bv.VolumeStatus -eq 'FullyEncrypted') {
        Log 'Disabling BitLocker on C: ...'
        Disable-BitLocker -MountPoint 'C:'
        Log 'Decryption started.'
    } else {
        Log 'BitLocker not enabled or already off.'
    }
} catch {
    Log "BitLocker check failed: $_"
}

Log '=== Setup 2.0 completed ==='
