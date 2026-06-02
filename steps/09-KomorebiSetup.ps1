function Step-KomorebiSetup {
    if (Test-StateCompleted "09-KomorebiSetup") { return }
    Write-Log "Setting up komorebi..." "INFO"

    $komorebiConfig = "$env:USERPROFILE\komorebi.json"
    $whkdConfig = "$env:USERPROFILE\.config\whkdrc"

    Copy-Item "$script:RootDir/configs/komorebi.json" $komorebiConfig -Force
    if (-not (Test-Path (Split-Path $whkdConfig -Parent))) {
        New-Item -Path (Split-Path $whkdConfig -Parent) -ItemType Directory -Force | Out-Null
    }
    Copy-Item "$script:RootDir/configs/whkdrc" $whkdConfig -Force
    Write-Log "  Deployed komorebi.json and whkdrc" "INFO"

    komorebic fetch-asc 2>&1 | Out-Null
    Write-Log "  Fetched application-specific configs" "INFO"

    $action = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument "-WindowStyle hidden -Command komorebic start --whkd"
    $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName "Komorebi" -Action $action -Trigger $trigger `
        -Settings $settings -Force -Description "Komorebi tiling window manager" 2>&1 | Out-Null

    Set-StateCompleted "09-KomorebiSetup"
    Write-Log "Komorebi configured with autostart" "SUCCESS"
}
Step-KomorebiSetup
