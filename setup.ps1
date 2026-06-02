param()

$ErrorActionPreference = "Stop"

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevateArgs = "-ExecutionPolicy Bypass -NoProfile -File `"$PSCommandPath`""
    Start-Process -FilePath "powershell.exe" -ArgumentList $elevateArgs -Verb RunAs
    exit 0
}

$script:RootDir = $PSScriptRoot
$script:SetupScript = $PSCommandPath
. "$script:RootDir/lib/State.ps1"
. "$script:RootDir/lib/Logger.ps1"
. "$script:RootDir/lib/Registry.ps1"
. "$script:RootDir/lib/Prompt.ps1"
. "$script:RootDir/lib/Reboot.ps1"

$stateFile = "$env:USERPROFILE\.win-setup\state.json"
Load-State $stateFile

$logPath = "$env:USERPROFILE\.win-setup\setup.log"
Initialize-Log $logPath

if (Test-ResumingAfterReboot) {
    Clear-ResumeAfterReboot
    Write-Log "Resuming after reboot..." "INFO"
}

$steps = Get-ChildItem "$script:RootDir/steps/*.ps1" | Sort-Object Name
foreach ($step in $steps) {
    try {
        . $step.FullName
    } catch {
        Write-Log "Step $($step.Name) failed: $($_.Exception.Message)" "ERROR"
    }
}

Write-Log "Setup complete." "SUCCESS"
