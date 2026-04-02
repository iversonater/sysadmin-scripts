<#
.SYNOPSIS
    Configures calendar permissions and processing settings for all Exchange Online room mailboxes.

.DESCRIPTION
    Connects to Exchange Online and iterates all room mailboxes, applying:
      - Calendar processing settings (preserves subject, removes organizer prefix)
      - Owner permission for a designated master user
      - Reviewer permission for the Default user

    Commonly used in medical and municipal environments where room calendars
    require a central admin to have full visibility and booking control.

.PARAMETER MasterUser
    UPN of the user to assign Owner rights on all room calendars.

.PARAMETER Rights
    Access rights to assign to the master user (default: Owner).

.PARAMETER RoomFilter
    Optional. Filters room mailboxes by display name or SMTP address wildcard.
    Leave blank to process all room mailboxes (default behavior).

.NOTES
    Author      : Dillon Iverson
    Version     : 1.0
    Run As      : Exchange Online Administrator
    Requires    : ExchangeOnlineManagement module
#>

[CmdletBinding()]
param (
    [string]$MasterUser  = 'user@example.com',
    [string]$Rights      = 'Owner',
    [string]$RoomFilter  = '*'
)

Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force

# --- Install/import ExchangeOnlineManagement if needed ---
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "ExchangeOnlineManagement module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name ExchangeOnlineManagement -Force -Scope CurrentUser
}
Import-Module ExchangeOnlineManagement -ErrorAction Stop

# --- Connect ---
Connect-ExchangeOnline

# --- Start transcript log ---
$LogPath = Join-Path $env:ProgramData "ScriptLogs\RoomCalendarPermissions_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
if (-not (Test-Path (Split-Path $LogPath))) {
    New-Item -Path (Split-Path $LogPath) -ItemType Directory -Force | Out-Null
}
Start-Transcript -Path $LogPath -Append
Write-Host "Log started: $LogPath"
Write-Host "Master User : $MasterUser"
Write-Host "Rights      : $Rights"
Write-Host "Room Filter : $RoomFilter"
Write-Host ""

# --- Process room mailboxes ---
$rooms = Get-Mailbox -RecipientTypeDetails RoomMailbox |
    Where-Object { $_.PrimarySmtpAddress -like $RoomFilter -or $_.DisplayName -like $RoomFilter }

Write-Host "Found $($rooms.Count) room mailbox(es) matching filter '$RoomFilter'." -ForegroundColor Cyan
Write-Host ""

foreach ($mailbox in $rooms) {
    $room    = $mailbox.PrimarySmtpAddress.ToString()
    $calPath = "${room}:\Calendar"

    Write-Host "Processing $room ..." -ForegroundColor Cyan

    try {
        # --- Calendar processing settings ---
        Write-Host "  Updating calendar processing settings..."
        Set-CalendarProcessing -Identity $room `
            -AddOrganizerToSubject $false `
            -DeleteSubject $false `
            -ErrorAction Stop

        # --- Master user permission ---
        $existing = Get-MailboxFolderPermission -Identity $calPath -User $MasterUser -ErrorAction SilentlyContinue
        if ($existing) {
            Set-MailboxFolderPermission -Identity $calPath -User $MasterUser -AccessRights $Rights -ErrorAction Stop
            Write-Host "  Updated $MasterUser to $Rights on $calPath"
        } else {
            Add-MailboxFolderPermission -Identity $calPath -User $MasterUser -AccessRights $Rights -ErrorAction Stop
            Write-Host "  Added $MasterUser as $Rights on $calPath"
        }

        # --- Default user permission ---
        try {
            Set-MailboxFolderPermission -Identity $calPath -User Default -AccessRights Reviewer -ErrorAction Stop
            Write-Host "  Set Default user to Reviewer on $calPath"
        } catch {
            Write-Warning "  Could not update Default permission for $room — $($_.Exception.Message)"
        }
    } catch {
        Write-Warning "  Failed on $calPath — $($_.Exception.Message)"
    }

    Write-Host "  Done." -ForegroundColor Green
    Write-Host ""
}

Write-Host "All room mailboxes processed." -ForegroundColor Yellow

# --- Disconnect and close log ---
Disconnect-ExchangeOnline -Confirm:$false
Stop-Transcript
