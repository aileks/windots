function Step-ExplorerTweaks {
    if (Test-StateCompleted "03-ExplorerTweaks") { return }
    Write-Log "Applying Explorer power-user tweaks..." "INFO"

    Set-RegistryBatch @{
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" = @{
            "HideFileExt"                   = @{ Value = 0 }
            "Hidden"                        = @{ Value = 1 }
            "ShowSyncProviderNotifications" = @{ Value = 0 }
            "ShowRecentFiles"               = @{ Value = 0 }
            "ShowFrequentFiles"             = @{ Value = 0 }
            "TaskbarDa"                     = @{ Value = 0 }
            "TaskbarAl"                     = @{ Value = 0 }
            "DisabledHotkeys"               = @{ Value = "hjklqmotpxynf1234567"; Type = "String" }
        }
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer" = @{
            "DisableSearchBoxSuggestions" = @{ Value = 1 }
        }
    }

    $classicMenuPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
    Set-RegistrySafe -Path $classicMenuPath -Name "(Default)" -Value "" -Type String

    Set-StateCompleted "03-ExplorerTweaks"
    Write-Log "Explorer configured" "SUCCESS"
}
Step-ExplorerTweaks
