Write-Output "Starting computer rename script..."

try {
    $maxLength = 15
    $baseName = "ABC26D-Serial"

    if ([string]::IsNullOrWhiteSpace($baseName)) {
        throw "Error: baseName is not set. Please define it at the top of the script."
    }

    $baseName = $baseName.ToUpper()
    $baseName = $baseName -replace '\s', ''

    $serialNumber = (Get-WmiObject win32_bios).SerialNumber

    $newName = $baseName + "-" + $serialNumber

    if ([string]::IsNullOrWhiteSpace($newName) -or $newName -match '[^a-zA-Z0-9-]') {
        Write-Output "Invalid computer name entered: $newName"
        throw "Error: Computer name can only contain letters, numbers, and hyphens."
    }

    $newNameLength = $newName.Length

    if ($newNameLength -gt $maxLength) {
        Write-Output "Computer would be renamed to: $newName"
        Write-Output "This is a length of $newNameLength characters"
        Write-Output "This would result in a name exceeding the max length."
        Write-Output "Dropping the necessary characters off beginning of the serial number..."

        $numOfExcessLength = $newName.Length - $maxLength
        $shortenedSerialNumber = $serialNumber.Substring($numOfExcessLength)
        $newName = $baseName + "-" + $shortenedSerialNumber
    }

    Write-Output "Renaming computer to: $newName"

    Rename-Computer -NewName $newName -Force

    Write-Output "Computer successfully renamed to: $newName"
    Write-Output "A restart is required for changes to take effect."
} catch {
    throw "Error renaming computer: $_"
}
