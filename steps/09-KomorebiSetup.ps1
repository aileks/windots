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

    if (-not (Get-Command komorebic -ErrorAction SilentlyContinue)) {
        Write-Log "  komorebic not found, skipping fetch-asc and autostart task" "WARN"
        return
    }

    komorebic fetch-asc 2>&1 | Write-Host
    Write-Log "  Fetched application-specific configs (applications.json)" "INFO"

    komorebic enable-autostart --whkd --bar 2>&1 | Write-Host
    Write-Log "  Enabled autostart (komorebi.lnk in shell:startup, starts komorebi + whkd + bar)" "INFO"

    Write-Log "Komorebi configured. It starts with whkd & bar at next sign-in." "SUCCESS"
    Write-Log "  To start now without signing out, run in a normal (non-admin) terminal: komorebic start --whkd --bar" "INFO"
}
Step-KomorebiSetup
