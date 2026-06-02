function Step-WslFeatures {
    if (Test-StateCompleted "01-WslFeatures") { return }
    Write-Log "Enabling WSL and Virtual Machine Platform..." "INFO"

    $needsReboot = $false
    foreach ($feature in @("Microsoft-Windows-Subsystem-Linux", "VirtualMachinePlatform")) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $feature).State
        if ($state -ne "Enabled") {
            $result = Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart
            if ($result.RestartNeeded) { $needsReboot = $true }
        }
    }

    Set-StateCompleted "01-WslFeatures"

    if ($needsReboot) {
        Register-ResumeAfterReboot $script:SetupScript
        Write-Log "Reboot required to finish enabling WSL features." "WARN"
        if (Ask-YesNo "Reboot now?" $true) {
            Restart-Computer -Force
        }
        exit 0
    }
}
Step-WslFeatures
