function Set-ObjectProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()]$Value
    )
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Invoke-WindowsTerminalSetup {
    param([switch]$ConfigureWslProfile)

    Write-Log "Configuring Windows Terminal" "INFO"
    $termPkgDir = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe"
    if (-not (Test-SoftwareInstalled -Commands @("wt.exe") -Detector { Test-Path $termPkgDir })) {
        Write-Log "Windows Terminal not detected" "ERROR"
        return $false
    }

    $termDir = "$termPkgDir\LocalState"
    $termSettingsPath = "$termDir\settings.json"
    if (-not (Test-Path $termDir)) { New-Item -Path $termDir -ItemType Directory -Force | Out-Null }
    if (Test-Path $termSettingsPath) {
        Copy-Item -LiteralPath $termSettingsPath `
            -Destination "$termSettingsPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $settings = Get-Content $termSettingsPath -Raw | ConvertFrom-Json
    } else {
        $settings = Get-Content "$script:RootDir/configs/windows/terminal/settings.json" -Raw | ConvertFrom-Json
    }
    $managed = Get-Content "$script:RootDir/configs/windows/terminal/settings.json" -Raw | ConvertFrom-Json

    Set-ObjectProperty $settings "alwaysShowTabs" $false
    Set-ObjectProperty $settings "showTabsInTitlebar" $false
    Set-ObjectProperty $settings "showTabsFullscreen" $false

    $shiftEnterId = "Windots.ShiftEnter"
    $managedShiftEnter = @($managed.actions | Where-Object { $_.id -eq $shiftEnterId }) | Select-Object -First 1
    $managedShiftEnterKey = @($managed.keybindings | Where-Object { $_.id -eq $shiftEnterId }) | Select-Object -First 1
    $actions = @($settings.actions | Where-Object {
        $_.id -ne $shiftEnterId -and $_.keys -ne "shift+enter"
    })
    $keybindings = @($settings.keybindings | Where-Object {
        $_.id -ne $shiftEnterId -and $_.keys -ne "shift+enter"
    })
    if ($managedShiftEnter -and $managedShiftEnterKey) {
        Set-ObjectProperty $settings "actions" @($actions + $managedShiftEnter)
        Set-ObjectProperty $settings "keybindings" @($keybindings + $managedShiftEnterKey)
    }

    $schemes = @($settings.schemes | Where-Object { $_.name -notin @("Ashen", "Cinder Grove") })
    Set-ObjectProperty $settings "schemes" @($schemes + $managed.schemes[0])

    if (-not $settings.profiles) { Set-ObjectProperty $settings "profiles" ([PSCustomObject]@{}) }
    if (-not $settings.profiles.defaults) { Set-ObjectProperty $settings.profiles "defaults" ([PSCustomObject]@{}) }
    $defaults = $settings.profiles.defaults
    foreach ($property in $managed.profiles.defaults.PSObject.Properties) {
        Set-ObjectProperty $defaults $property.Name $property.Value
    }
    $monoFontFace = Get-SelectedNerdFontMonoFace
    if (-not $monoFontFace) { $monoFontFace = "AdwaitaMono Nerd Font Mono" }
    Set-ObjectProperty $defaults "font" ([PSCustomObject]@{ face = $monoFontFace; size = 13 })

    if ($ConfigureWslProfile) {
        $ubuntuInstalled = (Get-Command Get-WslDistroNames -ErrorAction SilentlyContinue) -and
            (@(Get-WslDistroNames) -contains "Ubuntu")
        if ($ubuntuInstalled) {
            Set-ObjectProperty $settings "defaultProfile" "Ubuntu"
        }
        if (@($settings.disabledProfileSources) -contains "Windows.Terminal.Wsl") {
            $disabledSources = @($settings.disabledProfileSources | Where-Object { $_ -ne "Windows.Terminal.Wsl" })
            if ($disabledSources.Count -gt 0) {
                Set-ObjectProperty $settings "disabledProfileSources" $disabledSources
            } else {
                $settings.PSObject.Properties.Remove("disabledProfileSources")
            }
        }
    }

    $json = $settings | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($termSettingsPath, $json, [Text.UTF8Encoding]::new($false))
    Write-Log "Windows Terminal configured" "SUCCESS"
    return $true
}
