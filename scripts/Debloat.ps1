function Get-ProvisionedPackageNames {
    param([Parameter(Mandatory)][string]$PackageId)

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = @(& "$env:SystemRoot\System32\dism.exe" /Online /Get-ProvisionedAppxPackages /English 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        throw "DISM provision check failed with exit $exitCode"
    }

    $displayName = ""
    $packageNames = foreach ($line in $output) {
        $text = [string]$line
        if ($text -match '^DisplayName\s*:\s*(.+)$') {
            $displayName = $matches[1].Trim()
        }
        elseif ($text -match '^PackageName\s*:\s*(.+)$' -and $displayName -eq $PackageId) {
            $matches[1].Trim()
        }
    }
    return @($packageNames)
}

function Remove-InboxPackage {
    param([Parameter(Mandatory)][string]$PackageId)

    try {
        $installed = @(Get-AppxPackage -AllUsers -Name $PackageId -ErrorAction Stop)
    }
    catch {
        Write-Log "App check failed: $PackageId - $($_.Exception.Message)" "WARN"
        return $false
    }
    if ($installed.Count -eq 0) { return $true }

    $ok = $true
    try {
        $provisioned = @(Get-ProvisionedPackageNames -PackageId $PackageId)
    }
    catch {
        Write-Log "Provision check failed: $PackageId - $($_.Exception.Message)" "WARN"
        $provisioned = @()
        $ok = $false
    }
    foreach ($package in $installed) {
        try {
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
            Write-Log "App removed: $($package.Name)" "INFO"
        }
        catch {
            Write-Log "App removal failed: $($package.Name) - $($_.Exception.Message)" "WARN"
            $ok = $false
        }
    }
    foreach ($packageName in $provisioned) {
        try {
            $result = Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\dism.exe" -ArgumentList @(
                "/Online", "/Remove-ProvisionedAppxPackage", "/PackageName:$packageName", "/NoRestart", "/English"
            ) -NoConsole
            if (-not $result.Succeeded) { throw "DISM exited with $($result.ExitCode)" }
            Write-Log "Provision removed: $PackageId" "INFO"
        }
        catch {
            Write-Log "Provision removal failed: $PackageId - $($_.Exception.Message)" "WARN"
            $ok = $false
        }
    }
    return $ok
}

function Remove-OneDrivePath {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        Write-Log "Deleted: $Path" "INFO"
        return $true
    }
    catch {
        Write-Log "OneDrive path locked: $Path - $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Remove-OneDriveCompletely {
    Write-Log "Removing OneDrive" "INFO"
    Stop-Process -Name OneDrive, FileCoAuth -Force -ErrorAction SilentlyContinue
    $setup = @(
        "$env:SystemRoot\System32\OneDriveSetup.exe",
        "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($setup) {
        $result = Invoke-NativeCommand -FilePath $setup -ArgumentList @("/uninstall") -NoConsole
        if ($result.ExitCode -ne 0) {
            Write-Log "OneDrive uninstall failed: exit $($result.ExitCode)" "WARN"
        }
    }
    $paths = @(
        $env:OneDrive,
        (Join-Path $env:USERPROFILE "OneDrive"),
        (Join-Path $env:LOCALAPPDATA "Microsoft\OneDrive"),
        (Join-Path $env:PROGRAMDATA "Microsoft OneDrive"),
        (Join-Path $env:ProgramFiles "Microsoft OneDrive"),
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} "Microsoft OneDrive" })
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $failedPaths = @($paths | Where-Object { -not (Remove-OneDrivePath -Path $_) })
    if ($failedPaths.Count -gt 0) {
        $explorer = @(Get-Process -Name explorer -ErrorAction SilentlyContinue)
        if ($explorer.Count -gt 0) {
            try {
                $explorer | Stop-Process -Force -ErrorAction Stop
                $explorer | Wait-Process -ErrorAction SilentlyContinue
                Write-Log "Explorer stopped for OneDrive cleanup" "INFO"
                $failedPaths = @($failedPaths | Where-Object { -not (Remove-OneDrivePath -Path $_) })
            }
            finally {
                if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
                    Start-Process -FilePath "$env:SystemRoot\explorer.exe"
                    Write-Log "Explorer restarted" "INFO"
                }
            }
        }
    }
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "OneDrive" -ErrorAction SilentlyContinue
    if ($failedPaths.Count -gt 0) {
        Write-Log "OneDrive residue remains: $($failedPaths -join ', ')" "WARN"
        return $false
    }
    return $true
}

function Disable-WindowsAiComponents {
    $ok = $true
    try {
        $corePackages = @(Get-AppxPackage -AllUsers -Name "MicrosoftWindows.Client.CoreAI" -ErrorAction Stop)
    }
    catch {
        Write-Log "CoreAI check failed: $($_.Exception.Message)" "WARN"
        return $false
    }
    $provisioned = @()
    if ($corePackages.Count -gt 0) {
        try {
            $provisioned = @(Get-ProvisionedPackageNames -PackageId "MicrosoftWindows.Client.CoreAI")
        }
        catch {
            Write-Log "CoreAI provision check failed: $($_.Exception.Message)" "WARN"
            $ok = $false
        }
    }
    foreach ($package in $corePackages) {
        try {
            $sid = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value
            $eol = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\$sid\$($package.PackageFullName)"
            New-Item -Path $eol -Force | Out-Null
            Remove-AppxPackage -Package $package.PackageFullName -AllUsers -ErrorAction Stop
        }
        catch {
            Write-Log "CoreAI removal failed: $($_.Exception.Message)" "WARN"
            $ok = $false
        }
    }
    foreach ($packageName in $provisioned) {
        try {
            $result = Invoke-NativeCommand -FilePath "$env:SystemRoot\System32\dism.exe" -ArgumentList @(
                "/Online", "/Remove-ProvisionedAppxPackage", "/PackageName:$packageName", "/NoRestart", "/English"
            ) -NoConsole
            if (-not $result.Succeeded) { throw "DISM exited with $($result.ExitCode)" }
        }
        catch {
            Write-Log "CoreAI provision failed: $($_.Exception.Message)" "WARN"
            $ok = $false
        }
    }
    $service = Get-Service -Name "WSAIFabricSvc" -ErrorAction SilentlyContinue
    if ($service) {
        Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        Set-Service -Name $service.Name -StartupType Disabled
    }
    $feature = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
    if ($feature -and $feature.State -ne "Disabled") {
        $result = Disable-WindowsOptionalFeature -FeatureName "Recall" -Online -NoRestart -ErrorAction Stop
        if ($result.RestartNeeded) { Set-StateValue "rebootRequired" $true }
    }
    return $ok
}

function Invoke-WindowsDebloat {
    Write-Log "Removing inbox apps" "INFO"
    $packageIds = @(
        "Microsoft.WindowsFeedbackHub",
        "Microsoft.GetHelp",
        "Microsoft.MicrosoftOfficeHub",
        "Clipchamp.Clipchamp",
        "Microsoft.WindowsAlarms",
        "MicrosoftCorporationII.QuickAssist",
        "Microsoft.WindowsSoundRecorder",
        "Microsoft.MicrosoftStickyNotes",
        "Microsoft.Todos",
        "Microsoft.MicrosoftSolitaireCollection",
        "Microsoft.PowerAutomateDesktop",
        "Microsoft.Windows.DevHome",
        "Microsoft.BingWeather",
        "Microsoft.BingNews",
        "Microsoft.Copilot",
        "Microsoft.BingSearch",
        "Microsoft.StartExperiencesApp",
        "MicrosoftWindows.Client.WebExperience",
        "Microsoft.WidgetsPlatformRuntime"
    )
    $ok = $true
    foreach ($packageId in $packageIds) {
        if (-not (Remove-InboxPackage $packageId)) { $ok = $false }
    }
    try {
        if (-not (Remove-OneDriveCompletely)) { $ok = $false }
    }
    catch {
        Write-Log "OneDrive removal failed: $($_.Exception.Message)" "WARN"
        $ok = $false
    }
    if (-not (Disable-WindowsAiComponents)) { $ok = $false }
    return $ok
}
