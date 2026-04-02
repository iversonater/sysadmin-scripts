<#
.SYNOPSIS
    Installs or upgrades the WatchGuard Mobile VPN with SSL client to the latest version.

.DESCRIPTION
    Dynamically resolves the latest Windows installer from the WatchGuard software
    download portal. Backs up and restores per-user VPN profiles (AppData) and
    cached server/username registry values across the upgrade. Creates a desktop
    shortcut for all users on completion.

    Skips install if the currently installed version is already up-to-date.

.NOTES
    Author      : Dillon Iverson
    Version     : 1.1
    Run As      : Administrator or SYSTEM

    IMPORTANT - Download Page URL Dependency:
    The $downloadPageUrl below contains a WatchGuard/Salesforce familyId parameter.
    If WatchGuard restructures their download portal this URL may break and will
    need to be updated manually. Verify at: https://www.watchguard.com/wgrd-software/overview

    /autokill installer flag requires WatchGuard SSL VPN client 12.11.4 or newer.
#>

$ErrorActionPreference = 'Stop'

# Ensure TLS 1.2+ for Invoke-WebRequest
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# --- Configuration ---
# Verify this URL is still valid if the script stops resolving a download link
$downloadPageUrl = 'https://software.watchguard.com/SoftwareDownloads?current=true&familyId=a2RVr000000bJA9MAM'
$installedExe    = "C:\Program Files (x86)\WatchGuard\Mobile VPN\SSLvpn\wgsslvpnc.exe"
$wgRegPath       = 'HKCU:\Software\WatchGuard\SSLVPNClient\Settings'

# --- Prepare download folder ---
$downloadDir   = Join-Path $env:TEMP 'WatchGuard_SSLVPN'
$installerPath = Join-Path $downloadDir 'WG-MVPN-SSL-latest.exe'

if (-not (Test-Path $downloadDir)) {
    New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
}

# --- Resolve latest installer URL ---
Write-Output "Fetching WatchGuard download page: $downloadPageUrl"

try {
    $page = Invoke-WebRequest -Uri $downloadPageUrl -UseBasicParsing
} catch {
    Write-Error "Failed to retrieve WatchGuard download page: $($_.Exception.Message)"
    exit 1
}

if (-not $page.Links) {
    Write-Error "No links found on WatchGuard download page. Page structure may have changed."
    exit 1
}

$winLink = $page.Links |
    Where-Object {
        ($_.href -like '*cdn.watchguard.com*') -and
        (($_.innerText -like '*Windows*') -or ($_.outerHTML -like '*Windows*'))
    } |
    Select-Object -First 1

if (-not $winLink) {
    Write-Error "Could not locate a Windows installer link on the WatchGuard page."
    exit 1
}

$installerUrl = $winLink.href
Write-Output "Latest Windows SSL VPN installer URL: $installerUrl"

# --- Download installer ---
Write-Output "Downloading installer to $installerPath..."
try {
    Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath
} catch {
    Write-Error "Failed to download installer: $($_.Exception.Message)"
    exit 1
}

if (-not (Test-Path $installerPath)) {
    Write-Error "Installer file not found after download."
    exit 1
}

# --- Backup per-user AppData VPN profiles ---
$profileBackups  = @()
$profileListKey  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$backupRoot      = Join-Path $downloadDir 'MobileVPN_ProfileBackups'

try {
    $profileKeys = Get-ChildItem $profileListKey -ErrorAction Stop

    foreach ($key in $profileKeys) {
        $sid = $key.PSChildName
        if ($sid -notlike 'S-1-5-21-*') { continue }

        $profileProps = Get-ItemProperty -Path $key.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue
        $profilePath  = $profileProps.ProfileImagePath

        if (-not $profilePath -or -not (Test-Path $profilePath)) { continue }

        $vpnPath = Join-Path $profilePath 'AppData\Roaming\WatchGuard\Mobile VPN'
        if (Test-Path $vpnPath) {
            if (-not (Test-Path $backupRoot)) {
                New-Item -Path $backupRoot -ItemType Directory -Force | Out-Null
            }

            $safeSid    = ($sid -replace '[\\/:*?"<>|]', '_')
            $backupPath = Join-Path $backupRoot $safeSid

            Write-Output "Backing up Mobile VPN profile for SID $sid..."

            if (Test-Path $backupPath) { Remove-Item $backupPath -Recurse -Force }
            Copy-Item $vpnPath $backupPath -Recurse -Force

            $profileBackups += [pscustomobject]@{
                Sid         = $sid
                ProfilePath = $profilePath
                BackupPath  = $backupPath
            }
        }
    }

    if (-not $profileBackups) {
        Write-Output "No existing per-user Mobile VPN profile folders found to back up."
    }
} catch {
    Write-Output "Failed to enumerate user profiles for backup: $($_.Exception.Message)"
}

# --- Backup HKCU registry settings (server / username) ---
$SavedServer   = $null
$SavedUsername = $null

try {
    if (Test-Path $wgRegPath) {
        $wgProps       = Get-ItemProperty -Path $wgRegPath
        $SavedServer   = $wgProps.Server
        $SavedUsername = $wgProps.Username

        if ($SavedServer)   { Write-Output "Backed up VPN Server (HKCU): $SavedServer" }
        if ($SavedUsername) { Write-Output "Backed up VPN Username (HKCU): $SavedUsername" }
    } else {
        Write-Output "No existing HKCU SSLVPNClient settings found."
    }
} catch {
    Write-Output "Failed to back up HKCU SSLVPNClient settings: $($_.Exception.Message)"
}

# --- Version comparison ---
$installedVersion = $null
$installerVersion = $null

try {
    if (Test-Path $installedExe) {
        $installedVersionString = (Get-Item $installedExe).VersionInfo.ProductVersion
        if ($installedVersionString) {
            $installedVersion = [version]$installedVersionString
            Write-Output "Installed version: $installedVersionString"
        } else {
            Write-Output "Could not read installed version info."
        }
    } else {
        Write-Output "No existing SSL VPN client found — treating as fresh install."
    }

    $installerVersionString = (Get-Item $installerPath).VersionInfo.ProductVersion
    if ($installerVersionString) {
        $installerVersion = [version]$installerVersionString
        Write-Output "Installer version: $installerVersionString"
    } else {
        Write-Output "Could not read installer version info — proceeding with install."
    }
} catch {
    Write-Output "Version detection failed: $($_.Exception.Message). Proceeding with install."
}

if ($installedVersion -and $installerVersion) {
    if ($installedVersion -ge $installerVersion) {
        Write-Output "Installed version ($installedVersion) is already up-to-date. Skipping install."
        exit 0
    } else {
        Write-Output "Upgrading from $installedVersion to $installerVersion."
    }
} else {
    Write-Output "Version info incomplete — proceeding with install."
}

# --- Silent install ---
# /autokill requires WatchGuard SSL VPN client 12.11.4 or newer
$arguments = '/autokill /silent /verysilent /norestart'
Write-Output "Running silent install: `"$installerPath`" $arguments"

try {
    $process = Start-Process -FilePath $installerPath -ArgumentList $arguments -Wait -PassThru
} catch {
    Write-Error "Failed to start installer: $($_.Exception.Message)"
    exit 1
}

Write-Output "Installer exited with code: $($process.ExitCode)"

if ($process.ExitCode -ne 0) {
    Write-Error "Installer returned non-zero exit code: $($process.ExitCode)"
    exit $process.ExitCode
}

Write-Output "Installation completed successfully."

# --- Restore HKCU registry settings ---
try {
    if ($SavedServer -or $SavedUsername) {
        if (-not (Test-Path $wgRegPath)) { New-Item -Path $wgRegPath -Force | Out-Null }

        if ($SavedServer)   {
            Set-ItemProperty -Path $wgRegPath -Name 'Server' -Value $SavedServer
            Write-Output "Restored VPN Server value in HKCU."
        }
        if ($SavedUsername) {
            Set-ItemProperty -Path $wgRegPath -Name 'Username' -Value $SavedUsername
            Write-Output "Restored VPN Username value in HKCU."
        }
    } else {
        Write-Output "No HKCU Server/Username values to restore."
    }
} catch {
    Write-Output "Failed to restore HKCU SSLVPNClient settings: $($_.Exception.Message)"
}

# --- Restore per-user AppData VPN profiles ---
try {
    if ($profileBackups.Count -gt 0) {
        foreach ($b in $profileBackups) {
            $destPath = Join-Path $b.ProfilePath 'AppData\Roaming\WatchGuard\Mobile VPN'
            Write-Output "Restoring Mobile VPN profile for SID $($b.Sid)..."

            if (Test-Path $destPath) { Remove-Item $destPath -Recurse -Force }
            Copy-Item $b.BackupPath $destPath -Recurse -Force
        }
    } else {
        Write-Output "No Mobile VPN profile backups to restore."
    }
} catch {
    Write-Output "Failed to restore one or more Mobile VPN profiles: $($_.Exception.Message)"
}

# --- Create desktop shortcut for all users ---
try {
    $targetPath   = "C:\Program Files (x86)\WatchGuard\Mobile VPN\SSLvpn\wgsslvpnc.exe"
    $shortcutPath = "$env:PUBLIC\Desktop\WatchGuard SSL VPN.lnk"

    if (Test-Path $targetPath) {
        Write-Output "Creating desktop shortcut: $shortcutPath"

        $WScriptShell             = New-Object -ComObject WScript.Shell
        $Shortcut                 = $WScriptShell.CreateShortcut($shortcutPath)
        $Shortcut.TargetPath      = $targetPath
        $Shortcut.WorkingDirectory = Split-Path $targetPath
        $Shortcut.IconLocation    = "$targetPath, 0"
        $Shortcut.Save()
    } else {
        Write-Output "Warning: SSL VPN executable not found at expected path after install: $targetPath"
    }
} catch {
    Write-Output "Failed to create desktop shortcut: $($_.Exception.Message)"
}

exit 0
