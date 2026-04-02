<#
.SYNOPSIS
    Downloads and installs the Ookla Speedtest CLI to System32.

.DESCRIPTION
    Downloads the Speedtest CLI ZIP from Ookla, extracts speedtest.exe,
    and places it in C:\Windows\System32 so it is accessible from any
    execution context including RMM backstage and SYSTEM sessions.
    Skips installation if speedtest.exe is already present.

.NOTES
    Author      : Dillon Iverson
    Version     : 1.0
    Run As      : Administrator or SYSTEM
    Update URL  : Check https://www.speedtest.net/apps/cli for new releases
#>

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$ErrorActionPreference = "Stop"

# --- Configuration ---
# Update version and URL here when Ookla releases a new CLI version
# Latest: https://www.speedtest.net/apps/cli
$SpeedtestVersion   = "1.2.0"
$DownloadUrl        = "https://install.speedtest.net/app/cli/ookla-speedtest-$SpeedtestVersion-win64.zip"
$DestinationFolder  = "C:\Windows\System32"
$DestinationExe     = Join-Path $DestinationFolder "speedtest.exe"
$TempZipPath        = Join-Path $env:TEMP "speedtest-cli.zip"
$TempExtractPath    = Join-Path $env:TEMP "speedtest-extract"

# --- Skip if already installed ---
if (Test-Path $DestinationExe) {
    Write-Host "Speedtest CLI already exists at $DestinationExe. Skipping install."
    exit 0
}

# --- Download ---
Write-Host "Downloading Speedtest CLI v$SpeedtestVersion..."
try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempZipPath -UseBasicParsing
    Write-Host "Download complete."
} catch {
    Write-Host "Error: Download failed. Check URL or network connectivity." -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

# --- Extract ---
Write-Host "Extracting to temp folder..."
if (Test-Path $TempExtractPath) { Remove-Item $TempExtractPath -Recurse -Force }
Expand-Archive -Path $TempZipPath -DestinationPath $TempExtractPath -Force

# --- Move to System32 ---
$ExtractedExe = Join-Path $TempExtractPath "speedtest.exe"
if (Test-Path $ExtractedExe) {
    Move-Item -Path $ExtractedExe -Destination $DestinationFolder -Force
    Write-Host "speedtest.exe installed to $DestinationFolder."
} else {
    Write-Host "Error: speedtest.exe not found after extraction." -ForegroundColor Red
    exit 1
}

# --- Cleanup ---
Remove-Item -Path $TempZipPath -Force -ErrorAction SilentlyContinue
Remove-Item -Path $TempExtractPath -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Temp files cleaned up."

Write-Host "Done. Run 'speedtest' from any prompt or RMM session."
exit 0
