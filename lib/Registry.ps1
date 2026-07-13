$script:RegistryBackedUpPaths = @{}

function Get-SetupRegistryBackupTargets {
    @(
        "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"
        "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"
        "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"
        "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        "HKCU:\SOFTWARE\Microsoft\Clipboard"
        "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"
        "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"
        "HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
        "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    )
}

function ConvertTo-NativeRegistryPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -notmatch "^(HKLM|HKCU):\\(.+)$") {
        throw "Unsupported registry path: $Path"
    }
    "$($Matches[1])\$($Matches[2])"
}

function ConvertTo-RegFileRegistryPath {
    param([Parameter(Mandatory)][string]$Path)

    $nativePath = ConvertTo-NativeRegistryPath $Path
    if ($nativePath.StartsWith("HKLM\")) {
        return "HKEY_LOCAL_MACHINE\" + $nativePath.Substring(5)
    }
    "HKEY_CURRENT_USER\" + $nativePath.Substring(5)
}

function Get-MissingRegistryKeyFileContent {
    param([Parameter(Mandatory)][string]$Path)

    $regFilePath = ConvertTo-RegFileRegistryPath $Path
    "Windows Registry Editor Version 5.00`r`n`r`n[-$regFilePath]`r`n"
}

function Get-RegistryBackupFilePath {
    param(
        [Parameter(Mandatory)][string]$BackupDirectory,
        [Parameter(Mandatory)][string]$RegistryPath
    )

    $segments = (ConvertTo-NativeRegistryPath $RegistryPath) -split "\\"
    $directory = $BackupDirectory
    for ($i = 0; $i -lt $segments.Count - 1; $i++) {
        $directory = Join-Path $directory $segments[$i]
    }
    $leaf = $segments[-1] -replace '[<>:"/|?*]', '_'
    Join-Path $directory "$leaf.reg"
}

function Export-RegistryKey {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$BackupDirectory
    )

    try {
        $nativePath = ConvertTo-NativeRegistryPath $Path
        $destination = Get-RegistryBackupFilePath -BackupDirectory $BackupDirectory -RegistryPath $Path
        $parent = Split-Path $destination -Parent
        if (-not (Test-Path -LiteralPath $parent)) {
            New-Item -Path $parent -ItemType Directory -Force | Out-Null
        }

        if (Test-Path $Path) {
            $nativeResult = Invoke-NativeCommand -FilePath "reg.exe" -ArgumentList @(
                "export", $nativePath, $destination, "/y"
            ) -NoConsole
            if ($nativeResult.ExitCode -ne 0) {
                Write-Log "Registry export failed for $nativePath with exit code $($nativeResult.ExitCode)" "ERROR"
                return $false
            }
        } else {
            $content = Get-MissingRegistryKeyFileContent $Path
            [System.IO.File]::WriteAllText($destination, $content, [System.Text.Encoding]::Unicode)
        }
        return $true
    } catch {
        Write-Log "Registry export failed for ${Path}: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function New-RegistryBackup {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Paths
    )

    $backupDirectory = Join-Path $Root (Get-Date -Format "yyyyMMdd-HHmmss-fff")
    New-Item -Path $backupDirectory -ItemType Directory -Force | Out-Null
    $script:RegistryBackedUpPaths = @{}
    $succeeded = $true
    $exported = 0
    Write-Log "Backing up registry settings..." "INFO"
    foreach ($path in @($Paths | Select-Object -Unique)) {
        if (Export-RegistryKey -Path $path -BackupDirectory $backupDirectory) {
            $exported++
            $script:RegistryBackedUpPaths[$path] = $true
        } else {
            $succeeded = $false
        }
    }

    if ($succeeded) {
        Write-Log "Exported $exported registry subtrees to $backupDirectory" "SUCCESS"
    }
    [PSCustomObject]@{ Success = $succeeded; Path = $backupDirectory; Count = $exported }
}

function Test-RegistryPathBackedUp {
    param([Parameter(Mandatory)][string]$Path)
    $script:RegistryBackedUpPaths.ContainsKey($Path)
}

function Set-RegistrySafe {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [ValidateSet("DWord","String","ExpandString","QWord")]
        [string]$Type = "DWord",
        [switch]$PassThru
    )

    $success = $false
    try {
        if (-not (Test-RegistryPathBackedUp $Path)) {
            throw "Registry path was not included in the native backup: $Path"
        }
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        $propertyName = if ($Name -eq "(Default)") { "" } else { $Name }
        $kind = switch ($Type) {
            "DWord"        { [Microsoft.Win32.RegistryValueKind]::DWord }
            "String"       { [Microsoft.Win32.RegistryValueKind]::String }
            "ExpandString" { [Microsoft.Win32.RegistryValueKind]::ExpandString }
            "QWord"        { [Microsoft.Win32.RegistryValueKind]::QWord }
        }

        $root = $null
        $subKey = $null
        if ($Path -match "^HKLM:\\(.+)$") {
            $root = [Microsoft.Win32.Registry]::LocalMachine
            $subKey = $Matches[1]
        } elseif ($Path -match "^HKCU:\\(.+)$") {
            $root = [Microsoft.Win32.Registry]::CurrentUser
            $subKey = $Matches[1]
        } else {
            throw "Unsupported registry hive in path: $Path"
        }

        $key = $root.CreateSubKey($subKey)
        try {
            $existing = $key.GetValue($propertyName, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            $existingKind = if ($null -ne $existing) { $key.GetValueKind($propertyName) } else { $null }
            $valueDisplay = if ($Value -is [string]) { '"{0}"' -f $Value } else { [string]$Value }
            if ($null -eq $existing -or $existing -ne $Value -or $existingKind -ne $kind) {
                $key.SetValue($propertyName, $Value, $kind)
                Write-Log "  Set registry: ${Path}\${Name} = $valueDisplay ($Type)" "INFO"
            } else {
                Write-Log "  Registry already correct: ${Path}\${Name} = $valueDisplay ($Type)" "INFO"
            }
            $success = $true
        } finally {
            if ($key) { $key.Dispose() }
        }
    } catch {
        Write-Log "  Failed to set registry: ${Path}\${Name} - $($_.Exception.Message)" "WARN"
    }

    if ($PassThru) { return $success }
}

function Set-RegistryBatch {
    param(
        [Parameter(Mandatory)][hashtable]$Tweaks
    )

    $count = 0
    $failed = 0
    foreach ($path in $Tweaks.Keys) {
        $props = $Tweaks[$path]
        foreach ($name in $props.Keys) {
            $entry = $props[$name]
            $value = $entry.Value
            $type = if ($entry.ContainsKey("Type")) { $entry.Type } else { "DWord" }
            if (Set-RegistrySafe -Path $path -Name $name -Value $value -Type $type -PassThru) {
                $count++
            } else {
                $failed++
            }
        }
    }
    if ($failed -gt 0) {
        Write-Log "Applied $count registry values ($failed failed)" "WARN"
        return $false
    }
    Write-Log "Applied $count registry values" "SUCCESS"
    return $true
}
