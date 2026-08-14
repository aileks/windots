param()

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevateArgs = "-NoExit -ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $elevateArgs -Verb RunAs
    exit 0
}

$script:RootDir = $PSScriptRoot
$script:SetupScript = $PSCommandPath

foreach ($file in @(
        "lib/State.ps1",
        "lib/Logger.ps1",
        "lib/Link.ps1",
        "lib/Registry.ps1",
        "lib/Prompt.ps1",
        "lib/Reboot.ps1",
        "lib/Result.ps1"
    )) {
    . "$script:RootDir/$file"
}

Get-ChildItem "$script:RootDir/helpers/*.ps1" | Sort-Object Name | ForEach-Object { . $_.FullName }
Get-ChildItem "$script:RootDir/scripts/*.ps1" | Sort-Object Name | ForEach-Object { . $_.FullName }

if (-not (Test-SupportedEnvironment)) { exit 1 }

Write-Host ""
Write-Host "Installs software, optionally sets up WSL, symlinks configs, and applies system tweaks." -ForegroundColor Yellow
Write-Host "Backups and restore points enabled." -ForegroundColor Yellow
Write-Host "OneDrive is removed" -ForegroundColor Red
Write-Host ""
if (-not (Ask-YesNo "Continue with setup?" $false)) {
    Write-Host "Setup cancelled" -ForegroundColor Yellow
    exit 0
}
$setupWsl = Ask-YesNo "Set up WSL and Ubuntu?" $true

$stateDir = "$env:USERPROFILE\.dotfiles-state"
$stateFile = "$stateDir\state.json"
$logPath = "$stateDir\setup.log"
Load-State $stateFile | Out-Null
Initialize-Log $logPath
Restore-SystemRestoreFrequency

$initialRestoreSucceeded = New-SetupRestorePoint -Milestone "initial" `
    -Description "Windows setup script initial state"

if ($setupWsl -and -not (Test-WslPlatformEnabled)) {
    if (Ask-YesNo "WSL not enabled. Enable it and reboot?" $true) {
        if (-not (Enable-WslPlatformAndReboot)) { exit 1 }
    }
    Write-Log "WSL required" "WARN"
    exit 0
}

if (Test-ResumingAfterReboot) {
    Clear-ResumeAfterReboot
    Set-StateValue "rebootRequired" $false
    Write-Log "Setup resumed" "INFO"
}

$profileFiles = @(Get-ChildItem "$script:RootDir/data", "$script:RootDir/configs", "$script:RootDir/lib", `
        "$script:RootDir/helpers", "$script:RootDir/scripts" -File -Recurse | Sort-Object FullName)
$profileFiles += Get-Item -LiteralPath $PSCommandPath
$profileMaterial = ($profileFiles | ForEach-Object { "{0}:{1}" -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "|"
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $profileBytes = [Text.Encoding]::UTF8.GetBytes($profileMaterial)
    $profileFingerprint = ([BitConverter]::ToString($sha256.ComputeHash($profileBytes))).Replace("-", "")
}
finally {
    $sha256.Dispose()
}
if ((Get-StateValue "profileFingerprint") -ne $profileFingerprint) {
    Clear-StateCompleted
    Clear-ProfileSafetyMilestones
    Set-StateValue "profileFingerprint" $profileFingerprint
}

$actions = @(
    [PSCustomObject]@{ Id = "winget"; Name = "Windows Package Manager"; Run = { Ensure-WinGet } },
    [PSCustomObject]@{ Id = "windows-software"; Name = "Windows software"; Run = { Invoke-SoftwareInstall } },
    [PSCustomObject]@{ Id = "windows-cli"; Name = "PowerShell CLI tools"; Run = { Invoke-CliToolsInstall } },
    [PSCustomObject]@{ Id = "nerd-fonts"; Name = "Nerd fonts"; Run = { Invoke-NerdFontSetup } },
    [PSCustomObject]@{ Id = "npiperelay"; Name = "Bitwarden SSH relay"; Wsl = $true; Prerequisite = { Test-BitwardenInstalled }; PrerequisiteMessage = "Bitwarden is not installed"; Run = { Install-NpipeRelay } },
    [PSCustomObject]@{ Id = "ubuntu-environment"; Name = "Ubuntu environment"; Wsl = $true; Run = {
            $relayPath = Join-Path $env:LOCALAPPDATA "Programs\npiperelay\npiperelay.exe"
            if (-not ((Test-BitwardenInstalled) -and (Test-Path -LiteralPath $relayPath))) { $relayPath = "" }
            Invoke-WslBootstrap -RelayPath $relayPath
        } 
    },
    [PSCustomObject]@{ Id = "pre-tweaks-safety"; Name = "Pre-tweaks backup and restore point"; Run = {
            Initialize-PreTweaksSafety -BackupRoot "$stateDir\registry-backups" `
                -ProfileFingerprint $profileFingerprint
        } 
    },
    [PSCustomObject]@{ Id = "developer-tweaks"; Name = "Developer settings"; RequiresSafety = $true; Run = { Invoke-DeveloperTweaks } },
    [PSCustomObject]@{ Id = "explorer-tweaks"; Name = "Explorer and taskbar tweaks"; RequiresSafety = $true; Run = { Invoke-ExplorerTweaks } },
    [PSCustomObject]@{ Id = "privacy-tweaks"; Name = "Privacy and telemetry policies"; RequiresSafety = $true; Run = { Invoke-PrivacyTweaks } },
    [PSCustomObject]@{ Id = "service-tweaks"; Name = "Windows service settings"; RequiresSafety = $true; Run = { Invoke-ServiceTweaks } },
    [PSCustomObject]@{ Id = "windows-debloat"; Name = "Windows inbox app removal"; RequiresSafety = $true; Run = { Invoke-WindowsDebloat } },
    [PSCustomObject]@{ Id = "power-plan"; Name = "Ultimate Performance power plan"; Run = { Invoke-PowerPlanTweaks } },
    [PSCustomObject]@{ Id = "bitwarden-ssh"; Name = "Windows SSH agent handoff"; RequiresSafety = $true; Prerequisite = { Test-BitwardenInstalled }; PrerequisiteMessage = "Bitwarden is not installed; Windows ssh-agent was unchanged"; Run = { Disable-WindowsOpenSshAgent } },
    [PSCustomObject]@{ Id = "komorebi"; Name = "Komorebi configuration"; RequiresSafety = $true; Run = { Invoke-KomorebiSetup } },
    [PSCustomObject]@{ Id = "windows-terminal"; Name = "Windows Terminal"; Run = {
            Invoke-WindowsTerminalSetup -ConfigureWslProfile:$setupWsl
        } 
    },
    [PSCustomObject]@{ Id = "powershell-profile"; Name = "PowerShell profile"; Run = { Invoke-PowerShellProfileSetup } }
)

$results = @($actions | ForEach-Object { New-SetupResult -Id $_.Id -Name $_.Name })
$safetyReady = $false
$explorerChanged = $false

for ($i = 0; $i -lt $actions.Count; $i++) {
    $action = $actions[$i]
    $result = $results[$i]
    if (($action.PSObject.Properties.Name -contains "Wsl") -and $action.Wsl -eq $true -and -not $setupWsl) {
        $result.Status = "Skipped"
        $result.Message = "user choice"
        Write-Log "Skipped: $($action.Name) - user choice" "INFO"
        continue
    }
    if ($action.Id -ne "pre-tweaks-safety" -and (Test-StateCompleted $action.Id)) {
        $result.Status = "Skipped"
        $result.Message = "exists"
        Write-Log "Exists: $($action.Name)" "INFO"
        continue
    }
    if (($action.PSObject.Properties.Name -contains "RequiresSafety") -and
        $action.RequiresSafety -eq $true -and -not $safetyReady) {
        $result.Status = "Skipped"
        $result.Message = "safety dependency"
        Write-Log "Skipped: $($action.Name) - safety" "WARN"
        continue
    }
    if (($action.PSObject.Properties.Name -contains "Prerequisite") -and -not (& $action.Prerequisite)) {
        $result.Status = "Failed"
        $result.ExitCode = 1
        $result.Message = $action.PrerequisiteMessage
        Write-Log "Failed: $($action.Name) - $($result.Message)" "ERROR"
        Set-StateResult $result
        continue
    }

    $result.Status = "Running"
    $rebootWasRequired = (Get-StateValue "rebootRequired") -eq $true
    Write-Log "$($action.Name)" "INFO"
    try {
        $success = & $action.Run
        if ($action.Id -eq "windows-software") { $result.PackageResults = @($script:LastSoftwarePackageResults) }
        if ($success -eq $true) {
            $result.Status = "Success"
            if ($action.Id -eq "pre-tweaks-safety") { $safetyReady = $true }
            if ($action.Id -eq "explorer-tweaks") { $explorerChanged = $true }
            Write-Log "Done: $($action.Name)" "SUCCESS"
        }
        else {
            $result.Status = "Failed"
            $result.ExitCode = 1
            $failedPackages = @($result.PackageResults | Where-Object { $_.Status -eq "Failed" } | ForEach-Object { $_.Name })
            $result.Message = if ($failedPackages.Count) { "failed packages: $($failedPackages -join ', ')" } else { "see setup log" }
            Write-Log "Failed: $($action.Name) - $($result.Message)" "ERROR"
        }
    }
    catch {
        $result.Status = "Failed"
        $result.ExitCode = 1
        $result.Message = $_.Exception.Message
        Write-Log "$($action.Name) failed: $($_.Exception.Message)" "ERROR"
    }
    if (-not $rebootWasRequired -and (Get-StateValue "rebootRequired") -eq $true) { $result.RebootRequired = $true }
    Set-StateResult $result
}

if ($explorerChanged) {
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch {
        Write-Log "Explorer restart failed: $($_.Exception.Message)" "WARN"
    }
}

if (-not $initialRestoreSucceeded) {
    $results += New-SetupResult -Id "initial-restore-point" -Name "Initial restore point" `
        -Status "Failed" -ExitCode 1 -Message "creation failed"
}
$failed = @($results | Where-Object { $_.Status -eq "Failed" })
if ($failed.Count -eq 0) {
    if (-not (New-SetupRestorePoint -Milestone "complete" -Description "Windows setup script complete")) {
        $restoreResult = New-SetupResult -Id "final-restore-point" -Name "Final restore point" `
            -Status "Failed" -ExitCode 1 -Message "creation failed"
        $results += $restoreResult
        $failed = @($results | Where-Object { $_.Status -eq "Failed" })
    }
}
Show-SetupResults -Results $results -LogPath $logPath

if ($failed.Count -gt 0) {
    Write-Log "Setup failed: $($failed.Count) actions" "ERROR"
    Read-Host "Press Enter to close"
    exit 1
}

Write-Log "Setup complete" "SUCCESS"
if ((Get-StateValue "rebootRequired") -eq $true) {
    if (Ask-YesNo "A reboot is required. Reboot now?" $true) { Restart-Computer }
    else { Write-Log "Reboot skipped" "WARN" }
}

