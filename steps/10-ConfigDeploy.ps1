function Step-ConfigDeploy {
    if (Test-StateCompleted "10-ConfigDeploy") { return }
    Write-Log "Deploying config files..." "INFO"

    $nushellDir = "$env:APPDATA\nushell"
    if (-not (Test-Path $nushellDir)) { New-Item -Path $nushellDir -ItemType Directory -Force | Out-Null }
    Copy-Item "$script:RootDir/configs/nushell/env.nu" "$nushellDir\env.nu" -Force
    Copy-Item "$script:RootDir/configs/nushell/config.nu" "$nushellDir\config.nu" -Force
    Write-Log "  Deployed nushell config" "INFO"

    $termDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
    $termSettingsPath = "$termDir\settings.json"

    if (Test-Path $termSettingsPath) {
        $settings = Get-Content $termSettingsPath -Raw | ConvertFrom-Json -Depth 20

        $ashenScheme = Get-Content "$script:RootDir/configs/WindowsTerminal-settings.json" -Raw | ConvertFrom-Json -Depth 10
        $ashenColors = $ashenScheme.schemes[0]

        if (-not $settings.schemes) { $settings | Add-Member -NotePropertyName "schemes" -NotePropertyValue @() -Force }
        $existing = $settings.schemes | Where-Object { $_.name -eq "Ashen" }
        if (-not $existing) {
            $settings.schemes += $ashenColors
        }

        if (-not $settings.profiles.defaults) {
            $settings.profiles | Add-Member -NotePropertyName "defaults" -NotePropertyValue @{} -Force
        }
        $defaults = $settings.profiles.defaults
        $defaults | Add-Member -NotePropertyName "colorScheme" -NotePropertyValue "Ashen" -Force
        $defaults | Add-Member -NotePropertyName "useAcrylic" -NotePropertyValue $true -Force
        $defaults | Add-Member -NotePropertyName "opacity" -NotePropertyValue 92 -Force
        $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue @{ face = "CommitMono Nerd Font"; size = 11 } -Force
        $defaults | Add-Member -NotePropertyName "padding" -NotePropertyValue "12" -Force
        $defaults | Add-Member -NotePropertyName "cursorShape" -NotePropertyValue "bar" -Force

        $settings | ConvertTo-Json -Depth 20 | Set-Content $termSettingsPath -Encoding UTF8
        Write-Log "  Merged Ashen theme into Windows Terminal" "INFO"
    } else {
        Copy-Item "$script:RootDir/configs/WindowsTerminal-settings.json" $termSettingsPath -Force
        Write-Log "  Deployed Windows Terminal settings (fresh)" "INFO"
    }

    Set-StateCompleted "10-ConfigDeploy"
    Write-Log "Config files deployed" "SUCCESS"
}
Step-ConfigDeploy
