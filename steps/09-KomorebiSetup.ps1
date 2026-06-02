function Step-KomorebiSetup {
    if (Test-StateCompleted "09-KomorebiSetup") { return }
    Write-Log "Setting up komorebi..." "INFO"

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    $komorebiConfig = "$env:USERPROFILE\komorebi.json"
    $whkdConfig = "$env:USERPROFILE\.config\whkdrc"

    Copy-Item "$script:RootDir/configs/komorebi.json" $komorebiConfig -Force
    if (-not (Test-Path (Split-Path $whkdConfig -Parent))) {
        New-Item -Path (Split-Path $whkdConfig -Parent) -ItemType Directory -Force | Out-Null
    }
    Copy-Item "$script:RootDir/configs/whkdrc" $whkdConfig -Force
    Write-Log "  Deployed komorebi.json and whkdrc" "INFO"

    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
        Write-Log "  komorebic not found, skipping fetch-asc and autostart task" "WARN"
        return
    }

    komorebic fetch-asc 2>&1 | Write-Host
    Write-Log "  Fetched application-specific configs (applications.json)" "INFO"

    komorebic enable-autostart --whkd 2>&1 | Write-Host
    Write-Log "  Enabled autostart (komorebi.lnk in shell:startup, starts komorebi + whkd)" "INFO"

    Set-StateCompleted "09-KomorebiSetup"
    Write-Log "Komorebi configured. It starts with whkd at next sign-in." "SUCCESS"
    Write-Log "  To start now without signing out, run in a normal (non-admin) terminal: komorebic start --whkd" "INFO"
}
Step-KomorebiSetup
