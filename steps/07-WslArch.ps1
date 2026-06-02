function Step-WslArch {
    if (Test-StateCompleted "07-WslArch") { return }
    Write-Log "Setting up WSL with Arch Linux..." "INFO"

    Write-Log "  Updating WSL (web-download, no Store)..." "INFO"
    wsl --update --web-download 2>&1 | Write-Host

    wsl --set-default-version 2 2>&1 | Out-Null

    $distros = wsl --list --quiet 2>$null
    $archInstalled = $distros | Where-Object { $_ -match "archlinux" }
    if (-not $archInstalled) {
        Write-Log "  Installing Arch Linux distro (web-download, no-launch; create your Linux user afterward)..." "INFO"
        wsl --install --web-download -d archlinux --no-launch 2>&1 | Write-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Log "  Arch install did not complete (WSL features may need a reboot first)." "WARN"
            Write-Log "  Reboot, then re-run this step or run: wsl --install --web-download -d archlinux" "WARN"
        }
    }

    $wslConfigSource = "$script:RootDir/configs/wsl/.wslconfig"
    $wslConfigDest = "$env:USERPROFILE\.wslconfig"
    Copy-Item $wslConfigSource $wslConfigDest -Force
    Write-Log "  Deployed .wslconfig (mirrored networking)" "INFO"
    Write-Log "  configs/wsl/wsl.conf is provided to apply manually inside the distro (sudo cp to /etc/wsl.conf) after creating your Linux user." "INFO"

    Set-StateCompleted "07-WslArch"
    Write-Log "WSL Arch setup complete. Run 'wsl -d archlinux' to create your Linux user." "SUCCESS"
}
Step-WslArch
