function Step-WslUbuntu {
    if ($script:PersonalSetupSelected -ne $true) {
        return
    }

    if (Test-StateCompleted "Personal.WslUbuntu") { return }
    Write-Log "Installing WSL with Ubuntu..." "INFO"

    New-ConfigLink "$script:RootDir/configs/wsl/.wslconfig" "$env:USERPROFILE\.wslconfig"
    Write-Log "  Linked .wslconfig with mirrored networking" "INFO"

    $output = @(& wsl --install 2>&1)
    $exitCode = $LASTEXITCODE
    $outputText = @($output | ForEach-Object {
        ([string]$_).Replace([string][char]0, "").Trim()
    } | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    })
    $outputLevel = if ($exitCode -eq 0) { "INFO" } else { "WARN" }
    foreach ($line in $outputText) {
        Write-Log "  $line" $outputLevel
    }

    if ($exitCode -ne 0) {
        Write-Log "  wsl --install failed with exit code $exitCode" "ERROR"
        return
    }

    Write-Log "  configs/wsl/wsl.conf is provided to apply manually inside the distro after creating your Linux user." "INFO"

    Set-StateValue "rebootRequired" $true
    Set-StateCompleted "Personal.WslUbuntu"
    Write-Log "WSL with Ubuntu installed. Reboot, then launch Ubuntu to create your Linux user." "SUCCESS"
}
Step-WslUbuntu
