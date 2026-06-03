function Step-KomorebiSetup {
    Write-Log "Setting up komorebi..." "INFO"

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    $komorebiConfig = "$env:USERPROFILE\komorebi.json"
    $whkdConfig = "$env:USERPROFILE\.config\whkdrc"

    Copy-Item "$script:RootDir/configs/komorebi/komorebi.json" $komorebiConfig -Force
    Copy-Item "$script:RootDir/configs/komorebi/komorebi.bar.json" "$env:USERPROFILE\komorebi.bar.json" -Force
    if (-not (Test-Path (Split-Path $whkdConfig -Parent))) {
        New-Item -Path (Split-Path $whkdConfig -Parent) -ItemType Directory -Force | Out-Null
    }
    Copy-Item "$script:RootDir/configs/komorebi/whkdrc" $whkdConfig -Force
    Write-Log "  Deployed komorebi.json, komorebi.bar.json and whkdrc" "INFO"

    # Frees Win+L for whkd by disabling the OS lock; Win+Escape locks via KomorebiLock below.
    Set-RegistrySafe -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "DisableLockWorkstation" -Value 1 -Type DWord
    Write-Log "  Set DisableLockWorkstation=1 (frees Win+L for komorebi)" "INFO"

    # Elevated on-demand task: non-elevated whkd can't toggle the policy, so this re-enables locking, locks, then disables it again to keep Win+L free.
    $lockCmd = '/c reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 0 /f && rundll32.exe user32.dll,LockWorkStation && ping 127.0.0.1 -n 2 >nul && reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f'
    $action    = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $lockCmd
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName "KomorebiLock" -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log "  Registered KomorebiLock scheduled task (Win+Escape lock)" "INFO"

    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
        Write-Log "  komorebic not found, skipping fetch-asc and autostart task" "WARN"
        return
    }

    komorebic fetch-asc 2>&1 | Write-Host
    Write-Log "  Fetched application-specific configs" "INFO"

    Get-ScheduledTask -TaskName 'Komorebi' -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false

    komorebic enable-autostart --whkd --bar --masir 2>&1 | Write-Host
    Write-Log "  Enabled autostart" "INFO"

    Write-Log "Komorebi configured." "SUCCESS"
    Write-Log "  To start now without signing out, run in a normal (non-admin) terminal: komorebic start --whkd --bar --masir" "INFO"
}
Step-KomorebiSetup
