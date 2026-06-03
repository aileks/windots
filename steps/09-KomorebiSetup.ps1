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

    # Win+L is remapped to "focus right" in whkdrc; that only works if the OS lock is
    # disabled, so a hotkey daemon can intercept Win+L. This policy also disables all
    # locking, so Win+Escape locks via the elevated KomorebiLock task registered below.
    Set-RegistrySafe -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "DisableLockWorkstation" -Value 1 -Type DWord
    Write-Log "  Set DisableLockWorkstation=1 (frees Win+L for komorebi)" "INFO"

    # Win+Escape -> lock. whkd runs non-elevated and cannot write the protected Policies
    # key, so it triggers this elevated on-demand task (no UAC prompt). The task toggles
    # the policy off, locks, then restores it to keep the Win+L remap working.
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
    Write-Log "  Fetched application-specific configs (applications.json)" "INFO"

    komorebic enable-autostart --whkd --bar --masir 2>&1 | Write-Host
    Write-Log "  Enabled autostart (komorebi.lnk in shell:startup, starts komorebi + whkd + bar + masir)" "INFO"

    Write-Log "Komorebi configured." "SUCCESS"
    Write-Log "  To start now without signing out, run in a normal (non-admin) terminal: komorebic start --whkd --bar" "INFO"
}
Step-KomorebiSetup
