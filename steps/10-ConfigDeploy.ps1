function Step-ConfigDeploy {
    Write-Log "Deploying config files..." "INFO"

    $nushellDir = "$env:APPDATA\nushell"
    if (-not (Test-Path $nushellDir)) { New-Item -Path $nushellDir -ItemType Directory -Force | Out-Null }
    Copy-Item "$script:RootDir/configs/nushell/env.nu" "$nushellDir\env.nu" -Force
    Copy-Item "$script:RootDir/configs/nushell/config.nu" "$nushellDir\config.nu" -Force
    Write-Log "  Deployed nushell config" "INFO"

    $zedDir = "$env:APPDATA\Zed"
    if (-not (Test-Path $zedDir)) { New-Item -Path $zedDir -ItemType Directory -Force | Out-Null }
    Copy-Item "$script:RootDir/configs/zed/settings.json" "$zedDir\settings.json" -Force
    Copy-Item "$script:RootDir/configs/zed/keymap.json" "$zedDir\keymap.json" -Force
    Write-Log "  Deployed Zed config" "INFO"

    $nvimDir = "$env:LOCALAPPDATA\nvim"
    if (-not (Test-Path $nvimDir)) { New-Item -Path $nvimDir -ItemType Directory -Force | Out-Null }
    Copy-Item "$script:RootDir/configs/nvim/init.lua" "$nvimDir\init.lua" -Force
    Write-Log "  Deployed Neovim config (plugins auto-install on first launch)" "INFO"

    $termPkgDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe"
    $termDir = "$termPkgDir\LocalState"
    $termSettingsPath = "$termDir\settings.json"

    if (Test-Path $termSettingsPath) {
        $settings = Get-Content $termSettingsPath -Raw | ConvertFrom-Json

        $ashenScheme = Get-Content "$script:RootDir/configs/WindowsTerminal-settings.json" -Raw | ConvertFrom-Json
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
        $defaults | Add-Member -NotePropertyName "font" -NotePropertyValue @{ face = "CommitMono Nerd Font Mono"; size = 11 } -Force
        $defaults | Add-Member -NotePropertyName "padding" -NotePropertyValue "12" -Force
        $defaults | Add-Member -NotePropertyName "cursorShape" -NotePropertyValue "bar" -Force

        $settings | ConvertTo-Json -Depth 20 | Set-Content $termSettingsPath -Encoding UTF8
        Write-Log "  Merged Ashen theme into Windows Terminal" "INFO"
    } elseif (Test-Path $termPkgDir) {
        if (-not (Test-Path $termDir)) { New-Item -Path $termDir -ItemType Directory -Force | Out-Null }
        Copy-Item "$script:RootDir/configs/WindowsTerminal-settings.json" $termSettingsPath -Force
        Write-Log "  Deployed Windows Terminal settings (fresh)" "INFO"
    } else {
        Write-Log "  Windows Terminal not installed, skipping Terminal config" "WARN"
    }

    Write-Log "Config files deployed" "SUCCESS"
}
Step-ConfigDeploy
