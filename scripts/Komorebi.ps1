function Invoke-KomorebiSetup {
    if (-not (Test-SoftwareInstalled -Commands @("komorebic"))) {
        Write-Log "Komorebi is unavailable" "ERROR"
        return $false
    }

    $komorebiConfig = "$env:USERPROFILE\komorebi.json"
    $komorebiBarConfig = "$env:USERPROFILE\komorebi.bar.json"
    $whkdConfig = "$env:USERPROFILE\.config\whkdrc"

    New-ConfigLink "$script:RootDir/configs/windows/komorebi/komorebi.json" $komorebiConfig
    New-ConfigLink "$script:RootDir/configs/windows/komorebi/komorebi.bar.json" $komorebiBarConfig
    New-ConfigLink "$script:RootDir/configs/windows/komorebi/whkdrc" $whkdConfig
    Write-Log "Komorebi configs linked" "INFO"

    Write-Log "Configuring Komorebi" "INFO"

    Refresh-EnvironmentPath

    # Frees Win+L for whkd by disabling the OS lock; Win+Escape locks via KomorebiLock below.
    if (-not (Set-RegistrySafe -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
        -Name "DisableLockWorkstation" -Value 1 -Type DWord -PassThru)) { return $false }
    Write-Log "Komorebi keys configured" "INFO"

    # Elevated on-demand task: non-elevated whkd can't toggle the policy, so this re-enables locking, locks, then disables it again to keep Win+L free.
    $lockCmd = '/c reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 0 /f && rundll32.exe user32.dll,LockWorkStation && ping 127.0.0.1 -n 2 >nul && reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableLockWorkstation /t REG_DWORD /d 1 /f'
    $action    = New-ScheduledTaskAction -Execute "cmd.exe" -Argument $lockCmd
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
    $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                     -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
    Register-ScheduledTask -TaskName "KomorebiLock" -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    Write-Log "Komorebi lock registered" "INFO"

    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
        Write-Log "komorebic unavailable" "WARN"
        return $false
    }

    $nativeResult = Invoke-NativeCommand -FilePath "komorebic" -ArgumentList @(
        "check", "--komorebi-config", $komorebiConfig
    )
    if ($nativeResult.ExitCode -ne 0) {
        Write-Log "Komorebi configuration check failed" "ERROR"
        return $false
    }
    Write-Log "Komorebi configuration valid" "SUCCESS"

    $nativeResult = Invoke-NativeCommand -FilePath "komorebic" -ArgumentList @("fetch-asc")
    if ($nativeResult.ExitCode -ne 0) { return $false }
    Write-Log "Komorebi apps fetched" "INFO"

    Get-ScheduledTask -TaskName 'Komorebi' -ErrorAction SilentlyContinue |
        Unregister-ScheduledTask -Confirm:$false

    $nativeResult = Invoke-NativeCommand -FilePath "komorebic" -ArgumentList @(
        "enable-autostart", "--whkd", "--bar", "--masir"
    )
    if ($nativeResult.ExitCode -ne 0) { return $false }
    Write-Log "Komorebi autostart enabled" "INFO"

    Write-Log "Komorebi configured" "SUCCESS"
    Write-Log "Start: komorebic start --whkd --bar --masir" "INFO"
    return $true
}
