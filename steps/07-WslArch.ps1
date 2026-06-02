function Step-WslArch {
    if (Test-StateCompleted "07-WslArch") { return }
    Write-Log "Setting up WSL with Arch Linux..." "INFO"

    wsl --set-default-version 2 2>&1 | Out-Null

    $distros = wsl --list --quiet 2>$null
    $archInstalled = $distros | Where-Object { $_ -match "archlinux" }
    if (-not $archInstalled) {
        Write-Log "  Installing Arch Linux distro (no-launch; create your Linux user afterward)..." "INFO"
        wsl --install -d archlinux --no-launch 2>&1 | Write-Host
    }

    $wslConfigSource = "$script:RootDir/configs/wsl/.wslconfig"
    $wslConfigDest = "$env:USERPROFILE\.wslconfig"
    Copy-Item $wslConfigSource $wslConfigDest -Force
    Write-Log "  Deployed .wslconfig (mirrored networking)" "INFO"

    $wslConfContent = Get-Content "$script:RootDir/configs/wsl/wsl.conf" -Raw
    $wslConfEncoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($wslConfContent))
    wsl -d archlinux -- bash -c "echo '$wslConfEncoded' | base64 -d | sudo tee /etc/wsl.conf > /dev/null" 2>&1 | Out-Null
    Write-Log "  Deployed wsl.conf (systemd, automount)" "INFO"

    Set-StateCompleted "07-WslArch"
    Write-Log "WSL Arch setup complete. Run 'wsl -d archlinux' to create your Linux user." "SUCCESS"
}
Step-WslArch
