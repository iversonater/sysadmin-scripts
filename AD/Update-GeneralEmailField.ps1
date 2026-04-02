<#
.SYNOPSIS
    Bulk-updates AD user email addresses from an old domain to a new domain.

.DESCRIPTION
    Targets users within a specified OU whose mail attribute matches the old domain.
    Constructs new addresses in the format FirstNameLastInitial@NewDomain.
    Run with -WhatIf first to validate output before committing changes.

.PARAMETER OldDomain
    The domain to search for and replace (default: olddomain.com).

.PARAMETER NewDomain
    The replacement domain (default: newdomain.org).

.NOTES
    Author  : Dillon Iverson
    Version : 1.0
    Requires: ActiveDirectory module
    Usage   : .\Update-GeneralEmailFieldAD.ps1
              .\Update-GeneralEmailFieldAD.ps1 -WhatIf  (dry run)
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [string]$OldDomain  = "olddomain.com",
    [string]$NewDomain  = "newdomain.org",
    [string]$SearchBase = "OU=Syncing Users,OU=COMPANY,DC=example,DC=local"
)

Import-Module ActiveDirectory -ErrorAction Stop

# Start transcript log
$LogPath = "$PSScriptRoot\Update-ADMailDomain_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
Start-Transcript -Path $LogPath -Append
Write-Host "Log started: $LogPath"

$users = Get-ADUser `
    -SearchBase $SearchBase `
    -SearchScope Subtree `
    -Filter "mail -like '*@$($OldDomain)'" `
    -Properties givenName, sn, mail

Write-Host "Found $($users.Count) user(s) matching '@$OldDomain' in target OU."

foreach ($user in $users) {
    $firstName = $user.givenName
    $lastName  = $user.sn

    if ([string]::IsNullOrWhiteSpace($firstName) -or [string]::IsNullOrWhiteSpace($lastName)) {
        Write-Warning "Skipping $($user.SamAccountName) — missing givenName or sn."
        continue
    }

    $newMail = "$($firstName)$($lastName.Substring(0,1))@$NewDomain".ToLower()

    Write-Host "  $($user.SamAccountName): '$($user.mail)' -> '$newMail'"

    if ($PSCmdlet.ShouldProcess($user.DistinguishedName, "Set-ADUser EmailAddress to $newMail")) {
        Set-ADUser -Identity $user.DistinguishedName -EmailAddress $newMail
    }
}

Write-Host "Done."
Stop-Transcript
