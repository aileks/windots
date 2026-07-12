function Get-FontCatalog {
    $catalogPath = Join-Path $script:RootDir "data/fonts.json"
    if (-not (Test-Path $catalogPath)) {
        throw "Font catalog not found at $catalogPath"
    }

    Get-Content $catalogPath -Raw | ConvertFrom-Json
}

function Get-SelectedNerdFontMonoFace {
    $face = Get-StateValue "selectedNerdFontMonoFace"
    if ([string]::IsNullOrWhiteSpace($face)) { return "" }
    $face
}

function Get-SelectedNerdFontPropoFace {
    $face = Get-StateValue "selectedNerdFontPropoFace"
    if ([string]::IsNullOrWhiteSpace($face)) { return "" }
    $face
}

function Read-NerdFontSelection {
    $catalog = Get-FontCatalog
    $fonts = @($catalog.fonts)

    while ($true) {
        Write-Host ""
        Write-Host "Nerd Font" -ForegroundColor White

        for ($i = 0; $i -lt $fonts.Count; $i++) {
            Write-Host ("  {0}. {1}" -f ($i + 1), $fonts[$i].name) -ForegroundColor Cyan
        }

        $reply = Ask-Input "Select Nerd Font (one number, blank to skip)" ""
        if ([string]::IsNullOrWhiteSpace($reply)) { return $null }

        if ($reply -notmatch "^\d+$") {
            Write-Log "  Invalid selection: $reply" "WARN"
            continue
        }

        $index = [int]$reply
        if ($index -lt 1 -or $index -gt $fonts.Count) {
            Write-Log "  Invalid selection: $reply" "WARN"
            continue
        }

        return $fonts[$index - 1]
    }
}

function Install-NerdFontPackage {
    param(
        [Parameter(Mandatory)][string]$Package,
        [Parameter(Mandatory)][string]$Name
    )

    Write-Log "Installing $Name ($Package) via Scoop..." "INFO"
    & scoop install $Package 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Log "  Scoop install failed for $Package" "WARN"
        return $false
    }

    Write-Log "Installed $Name" "SUCCESS"
    return $true
}

function Invoke-NerdFontSetup {
    $font = Read-NerdFontSelection
    if ($null -eq $font) {
        Set-StateValue -Key "selectedNerdFontMonoPackage" -Value ""
        Set-StateValue -Key "selectedNerdFontPropoPackage" -Value ""
        Set-StateValue -Key "selectedNerdFontMonoFace" -Value ""
        Set-StateValue -Key "selectedNerdFontPropoFace" -Value ""
        return $true
    }

    if (-not (Ensure-Scoop)) { return $false }

    $catalog = Get-FontCatalog
    if (-not (Ensure-ScoopBucket -Name $catalog.bucket.name -Source $catalog.bucket.source)) {
        return $false
    }

    $monoInstalled = Install-NerdFontPackage -Package $font.monoPackage -Name "$($font.name) mono Nerd Font"
    $propoInstalled = Install-NerdFontPackage -Package $font.propoPackage -Name "$($font.name) proportional Nerd Font"
    if ($monoInstalled -and $propoInstalled) {
        Set-StateValue -Key "selectedNerdFontMonoPackage" -Value $font.monoPackage
        Set-StateValue -Key "selectedNerdFontPropoPackage" -Value $font.propoPackage
        Set-StateValue -Key "selectedNerdFontMonoFace" -Value $font.monoFace
        Set-StateValue -Key "selectedNerdFontPropoFace" -Value $font.propoFace
        return $true
    }

    Set-StateValue -Key "selectedNerdFontMonoPackage" -Value ""
    Set-StateValue -Key "selectedNerdFontPropoPackage" -Value ""
    Set-StateValue -Key "selectedNerdFontMonoFace" -Value ""
    Set-StateValue -Key "selectedNerdFontPropoFace" -Value ""
    return $false
}
