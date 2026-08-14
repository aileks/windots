function Get-SafetyMilestones {
    $value = Get-StateValue "safetyMilestones"
    $milestones = @{}
    if ($value -is [hashtable]) {
        foreach ($key in $value.Keys) { $milestones[$key] = $value[$key] }
    }
    elseif ($null -ne $value) {
        $value.PSObject.Properties | ForEach-Object { $milestones[$_.Name] = $_.Value }
    }
    $milestones
}

function Test-SafetyMilestone {
    param([Parameter(Mandatory)][string]$Name)
    $milestones = Get-SafetyMilestones
    $milestones.ContainsKey($Name) -and $milestones[$Name].completed -eq $true
}

function Set-SafetyMilestone {
    param(
        [Parameter(Mandatory)][string]$Name,
        [hashtable]$Details = @{}
    )
    $milestones = Get-SafetyMilestones
    $record = @{ completed = $true; completedAt = (Get-Date).ToString("o") }
    foreach ($key in $Details.Keys) { $record[$key] = $Details[$key] }
    $milestones[$Name] = [PSCustomObject]$record
    Set-StateValue "safetyMilestones" $milestones
}

function Clear-ProfileSafetyMilestones {
    $milestones = Get-SafetyMilestones
    foreach ($name in @("beforeTweaks", "complete")) { $milestones.Remove($name) }
    Remove-StateValue "registryBackupPath"
    Set-StateValue "safetyMilestones" $milestones
}

function Enable-SetupSystemRestore {
    $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $name = "SystemRestorePointCreationFrequency"
    try {
        if ($null -eq (Get-StateValue "systemRestoreFrequencyOriginal")) {
            $valueState = Get-RegistryValueState -Path $path -Name $name
            Set-StateValue "systemRestoreFrequencyOriginal" ([PSCustomObject]@{
                    existed = $valueState.Exists
                    value   = $valueState.Value
                })
        }
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        New-ItemProperty -Path $path -Name $name -Value 0 -PropertyType DWord -Force | Out-Null
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction Stop
        return $true
    }
    catch {
        Write-Log "Restore setup failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Restore-SystemRestoreFrequency {
    $original = Get-StateValue "systemRestoreFrequencyOriginal"
    if ($null -eq $original) { return }
    $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $name = "SystemRestorePointCreationFrequency"
    try {
        if ($original.existed -eq $true) {
            New-ItemProperty -Path $path -Name $name -Value ([int]$original.value) -PropertyType DWord -Force | Out-Null
        }
        elseif ((Get-RegistryValueState -Path $path -Name $name).Exists) {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        }
        Remove-StateValue "systemRestoreFrequencyOriginal"
    }
    catch {
        Write-Log "Restore frequency failed: $($_.Exception.Message)" "WARN"
    }
}

function New-SetupRestorePoint {
    param(
        [Parameter(Mandatory)][string]$Milestone,
        [Parameter(Mandatory)][string]$Description
    )
    if (Test-SafetyMilestone $Milestone) {
        Write-Log "Restore point exists: $Description" "INFO"
        return $true
    }
    try {
        if (-not (Enable-SetupSystemRestore)) { return $false }
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Set-SafetyMilestone $Milestone @{ description = $Description }
        Write-Log "Restore point created: $Description" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Restore point failed: $Description - $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        Restore-SystemRestoreFrequency
    }
}

function Test-RegistryBackupMilestone {
    param(
        [Parameter(Mandatory)]$Milestone,
        [Parameter(Mandatory)][string]$ProfileFingerprint,
        [Parameter(Mandatory)][string[]]$RegistryPaths
    )

    if ($Milestone.profileFingerprint -ne $ProfileFingerprint) { return $false }
    $backupPath = [string]$Milestone.registryBackupPath
    if ([string]::IsNullOrWhiteSpace($backupPath) -or -not (Test-Path -LiteralPath $backupPath -PathType Container)) {
        return $false
    }
    $savedPaths = @($Milestone.registryPaths)
    if (@($savedPaths | Where-Object { $_ -notin $RegistryPaths }).Count -gt 0 -or
        @($RegistryPaths | Where-Object { $_ -notin $savedPaths }).Count -gt 0) {
        return $false
    }
    foreach ($path in $RegistryPaths) {
        $file = Get-RegistryBackupFilePath -BackupDirectory $backupPath -RegistryPath $path
        $item = Get-Item -LiteralPath $file -ErrorAction SilentlyContinue
        if ($null -eq $item -or $item.Length -eq 0) { return $false }
    }
    return $true
}

function Initialize-PreTweaksSafety {
    param(
        [Parameter(Mandatory)][string]$BackupRoot,
        [Parameter(Mandatory)][string]$ProfileFingerprint
    )
    $registryPaths = @(Get-SetupRegistryBackupTargets | Select-Object -Unique)
    $milestones = Get-SafetyMilestones
    $milestone = $milestones["beforeTweaks"]
    if ($null -ne $milestone -and
        (Test-RegistryBackupMilestone -Milestone $milestone -ProfileFingerprint $ProfileFingerprint `
            -RegistryPaths $registryPaths)) {
        $script:RegistryBackedUpPaths = @{}
        foreach ($path in $registryPaths) { $script:RegistryBackedUpPaths[$path] = $true }
        Write-Log "Registry backup verified" "SUCCESS"
        return $true
    }
    if ($null -ne $milestone) {
        $milestones.Remove("beforeTweaks")
        Set-StateValue "safetyMilestones" $milestones
    }

    $registryBackup = New-RegistryBackup -Root $BackupRoot -Paths $registryPaths
    if (-not $registryBackup.Success) { return $false }
    Set-StateValue "registryBackupPath" $registryBackup.Path
    if (-not (New-SetupRestorePoint -Milestone "beforeTweaks" -Description "Windows setup script before tweaks")) {
        return $false
    }
    $milestones = Get-SafetyMilestones
    $milestone = $milestones["beforeTweaks"]
    $milestone | Add-Member -NotePropertyName registryBackupPath -NotePropertyValue $registryBackup.Path -Force
    $milestone | Add-Member -NotePropertyName profileFingerprint -NotePropertyValue $ProfileFingerprint -Force
    $milestone | Add-Member -NotePropertyName registryPaths -NotePropertyValue $registryPaths -Force
    $milestones["beforeTweaks"] = $milestone
    Set-StateValue "safetyMilestones" $milestones
    return $true
}
