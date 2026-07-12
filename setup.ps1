param()

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevateArgs = "-NoExit -ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $elevateArgs -Verb RunAs
    exit 0
}

$script:RootDir = $PSScriptRoot
$script:SetupScript = $PSCommandPath
$script:TuiActive = $false

foreach ($file in @(
    "lib/State.ps1",
    "lib/Logger.ps1",
    "lib/Link.ps1",
    "lib/Registry.ps1",
    "lib/Prompt.ps1",
    "lib/Reboot.ps1",
    "lib/Result.ps1",
    "lib/Tui.ps1"
)) {
    . "$script:RootDir/$file"
}

Get-ChildItem "$script:RootDir/helpers/*.ps1" | Sort-Object Name | ForEach-Object { . $_.FullName }
Get-ChildItem "$script:RootDir/personal/*.ps1" | Sort-Object Name | ForEach-Object { . $_.FullName }

$stateDir = "$env:USERPROFILE\.win-setup"
$stateFile = "$stateDir\state.json"
$logPath = "$stateDir\setup.log"
Load-State $stateFile | Out-Null
Initialize-Log $logPath

if (-not (Test-WslPlatformEnabled)) {
    if (Ask-YesNo "WSL not enabled! Would you like to enable and reboot?" $true) {
        if (-not (Enable-WslPlatformAndReboot)) { exit 1 }
    }
    Write-Log "Setup requires WSL. No changes were applied." "WARN"
    exit 0
}

if (Test-ResumingAfterReboot) {
    Clear-ResumeAfterReboot
    Set-StateValue "rebootRequired" $false
    Write-Log "Resumed after WSL enablement reboot" "INFO"
}

if (-not (Initialize-SetupRepository)) { exit 1 }

Write-Host ""
Write-Host "win-setup changes Windows policies and privacy settings, installs software, links configs," -ForegroundColor Yellow
Write-Host "configures Ubuntu, and may require another reboot. Existing configs are timestamp-backed up." -ForegroundColor Yellow
Write-Host "Affected registry subtrees are exported to timestamped native .reg files before changes." -ForegroundColor Yellow
Write-Host "Bitwarden SSH use disables the Windows OpenSSH Authentication Agent service." -ForegroundColor Yellow
Write-Host ""
if (-not (Ask-YesNo "Continue with setup?" $false)) {
    Write-Log "Setup cancelled before changes" "INFO"
    exit 0
}

$catalog = Get-SoftwareCatalog
$selection = Read-OptionalSoftwareTui -Items @($catalog.optional)
if ($selection.Cancelled) {
    Write-Log "Setup cancelled from software selection" "INFO"
    exit 0
}
$optionalItems = @($selection.Items)

$profileFiles = @(Get-ChildItem "$script:RootDir/data", "$script:RootDir/configs", "$script:RootDir/lib", `
    "$script:RootDir/helpers", "$script:RootDir/personal" -File -Recurse | Sort-Object FullName)
$profileFiles += Get-Item -LiteralPath $PSCommandPath
$profileMaterial = ($profileFiles | ForEach-Object { "{0}:{1}" -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join "|"
$sha256 = [System.Security.Cryptography.SHA256]::Create()
try {
    $profileBytes = [Text.Encoding]::UTF8.GetBytes($profileMaterial + "|" + ((@($optionalItems.id) | Sort-Object) -join ","))
    $profileFingerprint = ([BitConverter]::ToString($sha256.ComputeHash($profileBytes))).Replace("-", "")
} finally {
    $sha256.Dispose()
}
if ((Get-StateValue "profileFingerprint") -ne $profileFingerprint) {
    Clear-StateCompleted
    Set-StateValue "profileFingerprint" $profileFingerprint
}

$registryActionIds = @("adwaita-font", "developer-tweaks", "explorer-tweaks", "privacy-tweaks", "komorebi")
$registryBackupNeeded = @($registryActionIds | Where-Object { -not (Test-StateCompleted $_) }).Count -gt 0
if ($registryBackupNeeded) {
    $registryBackup = New-RegistryBackup -Root "$stateDir\registry-backups" -Paths @(Get-SetupRegistryBackupTargets)
    if (-not $registryBackup.Success) {
        Write-Log "Registry backup is incomplete. No setup actions were applied." "ERROR"
        Read-Host "Press Enter to close"
        exit 1
    }
    Set-StateValue "registryBackupPath" $registryBackup.Path
}

$actions = @(
    [PSCustomObject]@{ Id = "windows-software"; Name = "Windows software"; Run = { Invoke-SoftwareInstall -OptionalItems $optionalItems } },
    [PSCustomObject]@{ Id = "windows-cli"; Name = "Windows fallback CLI tools"; Run = { Invoke-CliToolsInstall } },
    [PSCustomObject]@{ Id = "npiperelay"; Name = "Bitwarden SSH relay"; Run = { Install-NpipeRelay } },
    [PSCustomObject]@{ Id = "adwaita-font"; Name = "Adwaita Mono Nerd Font"; Run = { Invoke-NerdFontSetup } },
    [PSCustomObject]@{ Id = "developer-tweaks"; Name = "Developer mode, paths, symlinks, and sudo"; Run = { Invoke-DeveloperTweaks } },
    [PSCustomObject]@{ Id = "explorer-tweaks"; Name = "Explorer and taskbar tweaks"; Run = { Invoke-ExplorerTweaks } },
    [PSCustomObject]@{ Id = "privacy-tweaks"; Name = "Privacy and telemetry policies"; Run = { Invoke-PrivacyTweaks } },
    [PSCustomObject]@{ Id = "power-plan"; Name = "Ultimate Performance power plan"; Run = { Invoke-PowerPlanTweaks } },
    [PSCustomObject]@{ Id = "bitwarden-ssh"; Name = "Windows SSH agent handoff"; Run = { Disable-WindowsOpenSshAgent } },
    [PSCustomObject]@{ Id = "ubuntu-environment"; Name = "Ubuntu daily environment"; Run = { Invoke-WslBootstrap } },
    [PSCustomObject]@{ Id = "vscode-wsl"; Name = "VS Code WSL extension"; Run = { Install-VsCodeWslExtension } },
    [PSCustomObject]@{ Id = "komorebi"; Name = "Komorebi configuration"; Run = { Invoke-KomorebiSetup } },
    [PSCustomObject]@{ Id = "configs"; Name = "Windows config deployment"; Run = { Invoke-ConfigDeploy } },
    [PSCustomObject]@{ Id = "powershell-profile"; Name = "Minimal PowerShell profile"; Run = { Invoke-PowerShellProfileSetup } }
)

$results = @($actions | ForEach-Object { New-SetupResult -Id $_.Id -Name $_.Name })
Show-SetupProgress -Results $results

for ($i = 0; $i -lt $actions.Count; $i++) {
    $action = $actions[$i]
    $result = $results[$i]

    if (Test-StateCompleted $action.Id) {
        $result.Status = "Skipped"
        $result.Message = "already completed"
        Show-SetupProgress -Results $results
        continue
    }

    $result.Status = "Running"
    $rebootWasRequired = (Get-StateValue "rebootRequired") -eq $true
    Show-SetupProgress -Results $results
    try {
        $success = & $action.Run
        if ($success -eq $true) {
            $result.Status = "Success"
        } else {
            $result.Status = "Failed"
            $result.ExitCode = 1
            $result.Message = "see setup log"
        }
    } catch {
        $result.Status = "Failed"
        $result.ExitCode = 1
        $result.Message = $_.Exception.Message
        Write-Log "$($action.Name) failed: $($_.Exception.Message)" "ERROR"
    }

    $rebootIsRequired = (Get-StateValue "rebootRequired") -eq $true
    if (-not $rebootWasRequired -and $rebootIsRequired) { $result.RebootRequired = $true }
    Set-StateResult $result
    Show-SetupProgress -Results $results
}

try {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
} catch {
    Write-Log "Explorer restart failed: $($_.Exception.Message)" "WARN"
}

$failed = @($results | Where-Object { $_.Status -eq "Failed" })
Show-SetupResults -Results $results -LogPath $logPath

if ($failed.Count -gt 0) {
    Write-Log "Setup finished with $($failed.Count) failed required actions" "ERROR"
    Read-Host "Press Enter to close"
    exit 1
}

Write-Log "Setup complete" "SUCCESS"
if ((Get-StateValue "rebootRequired") -eq $true) {
    if (Ask-YesNo "A reboot is required. Reboot now?" $true) {
        Restart-Computer
    } else {
        Write-Log "Reboot skipped" "WARN"
    }
}
