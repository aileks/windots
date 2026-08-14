function Invoke-DeveloperTweaks {
    Write-Log "Configuring developer settings" "INFO"
    $registryOk = Set-RegistryBatch @{
        "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"              = @{
            "LongPathsEnabled" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" = @{
            "AllowDevelopmentWithoutDevLicense" = @{ Value = 1 }
        }
    }

    $fsutilResult = Invoke-NativeCommand -FilePath "fsutil" -ArgumentList @(
        "behavior", "set", "SymlinkEvaluation", "L2L:1", "R2R:1", "L2R:1", "R2L:1"
    )
    $fsutilOk = $fsutilResult.ExitCode -eq 0
    if (-not $fsutilOk) { Write-Log "Symlink evaluation setup failed" "ERROR" }

    $sudoOk = $true
    if (Get-Command sudo -ErrorAction SilentlyContinue) {
        $sudoResult = Invoke-NativeCommand -FilePath "sudo" -ArgumentList @("config", "--enable", "normal")
        $sudoOk = $sudoResult.ExitCode -eq 0
        if (-not $sudoOk) { Write-Log "Sudo for Windows setup failed" "ERROR" }
    }
    else {
        Write-Log "Sudo unavailable" "ERROR"
        $sudoOk = $false
    }

    return $registryOk -and $fsutilOk -and $sudoOk
}
