function Step-WslUbuntu {
    if ($script:PersonalSetupSelected -ne $true) {
        return
    }

    $ubuntuDistro = "Ubuntu"

    Refresh-EnvironmentPath
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        Write-Log "  WSL is not installed or not available on PATH; reboot after enabling WSL features, then re-run setup." "WARN"
        return
    }

    $wslStatus = @(wsl --status 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $statusText = ($wslStatus | ForEach-Object {
            ([string]$_).Replace([string][char]0, "").Trim()
        } | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }) -join " "

        if (-not [string]::IsNullOrWhiteSpace($statusText)) {
            Write-Log "  WSL status check failed: $statusText" "WARN"
        }
        Write-Log "  WSL is not installed or not ready; reboot after enabling WSL features, then re-run setup." "WARN"
        return
    }

    New-ConfigLink "$script:RootDir/configs/wsl/.wslconfig" "$env:USERPROFILE\.wslconfig"
    Write-Log "  Linked .wslconfig with mirrored networking" "INFO"

    $distros = @(wsl --list --quiet 2>$null | ForEach-Object {
        $_.Replace([string][char]0, "").Trim()
    } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    $ubuntuInstalled = $distros -contains $ubuntuDistro

    if ((Test-StateCompleted "Personal.WslUbuntu") -and $ubuntuInstalled) { return }
    Write-Log "Setting up WSL with Ubuntu..." "INFO"

    Write-Log "  Updating WSL via web-download instead of the Store..." "INFO"
    wsl --update --web-download 2>&1 | Write-Host

    wsl --set-default-version 2 2>&1 | Out-Null

    if (-not $ubuntuInstalled) {
        Write-Log "  Installing the default Ubuntu distro via web-download with no-launch; create your Linux user afterward..." "INFO"
        wsl --install --web-download --no-launch 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Log "  Ubuntu install did not complete; WSL features may need a reboot first." "WARN"
            Write-Log "  Reboot, then re-run this step or run: wsl --install --web-download --no-launch" "WARN"
            return
        }
    }

    Write-Log "  configs/wsl/wsl.conf is provided to apply manually inside the distro after creating your Linux user." "INFO"

    Set-StateValue "rebootRequired" $false
    Set-StateCompleted "Personal.WslUbuntu"
    Write-Log "WSL Ubuntu setup complete. Run 'wsl -d $ubuntuDistro' to create your Linux user." "SUCCESS"
}
Step-WslUbuntu
