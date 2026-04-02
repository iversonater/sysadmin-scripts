<#
.SYNOPSIS
    Runs DISM RestoreHealth followed by SFC /scannow with full logging.

.DESCRIPTION
    Repairs Windows component store and system file integrity. Logs to
    C:\ProgramData\ScriptLogs\ with a timestamped filename. Does not
    force a reboot regardless of outcome — reports exit codes only.

.NOTES
    Author      : Dillon Iverson
    Version     : 1.1
    Run As      : SYSTEM or local Administrator
    Exit Codes  : 0 = success or minor SFC self-repair, 1 = action required
    SFC Codes   : 0 = no violations, 1 = repaired, 2 = could not repair / reboot pending
#>

Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
$ErrorActionPreference = "Stop"

$logDir = Join-Path $env:ProgramData "ScriptLogs"
if (!(Test-Path $logDir)) { New-Item -Path $logDir -ItemType Directory -Force | Out-Null }

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logFile   = Join-Path $logDir "DISM_SFC_$timestamp.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Run-Command {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )
    Write-Log "Running: $FilePath $($Arguments -join ' ')"
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    Write-Log "Exit code: $($p.ExitCode)"
    return $p.ExitCode
}

Write-Log "=== Starting DISM + SFC ==="
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User Context: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"

# DISM RestoreHealth
$dismExit = Run-Command -FilePath "dism.exe" -Arguments @("/Online", "/Cleanup-Image", "/RestoreHealth")

# Capture DISM summary lines (best-effort)
try {
    $dismSummary = (Get-Content $logFile -ErrorAction SilentlyContinue |
        Select-String -Pattern "The restore operation completed successfully|The component store corruption was repaired|No component store corruption detected|Error:" -SimpleMatch).Line
    if ($dismSummary) { $dismSummary | ForEach-Object { Write-Log "DISM Summary: $_" } }
} catch {}

# SFC ScanNow
$sfcExit = Run-Command -FilePath "sfc.exe" -Arguments @("/scannow")

Write-Log "=== Completed DISM + SFC ==="
Write-Log "DISM Exit: $dismExit | SFC Exit: $sfcExit"
Write-Log "Log saved: $logFile"

# Exit 0 if both clean or SFC self-repaired (exit 1)
# Exit 1 if DISM failed or SFC could not repair (exit 2+)
if ($dismExit -ne 0 -or ($sfcExit -ne 0 -and $sfcExit -ne 1)) {
    exit 1
}
exit 0
