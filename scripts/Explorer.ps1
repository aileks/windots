function Set-ExplorerFolderDefaults {
    $bagsPath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"
    $bagMruPath = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
    try {
        Remove-Item -Path $bagsPath -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $bagMruPath -Recurse -Force -ErrorAction SilentlyContinue
        $allFolders = "$bagsPath\AllFolders\Shell"
        New-Item -Path $allFolders -Force | Out-Null
        New-ItemProperty -Path $allFolders -Name "FolderType" -Value "NotSpecified" `
            -PropertyType String -Force | Out-Null

        $tempFile = Join-Path $env:TEMP "windows-setup-script-folder-types-$([guid]::NewGuid()).reg"
        $importFile = "$tempFile.import.reg"
        try {
            $export = Invoke-NativeCommand -FilePath "reg.exe" -ArgumentList @(
                "export", "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes", $tempFile, "/y"
            ) -NoConsole
            if ($export.ExitCode -ne 0) { throw "could not export machine FolderTypes" }
            $content = Get-Content -LiteralPath $tempFile -Raw
            $content = $content.Replace(
                "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes",
                "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes")
            [IO.File]::WriteAllText($importFile, $content, [Text.Encoding]::Unicode)
            $import = Invoke-NativeCommand -FilePath "reg.exe" -ArgumentList @("import", $importFile, "/reg:64") -NoConsole
            if ($import.ExitCode -ne 0) { throw "could not import per-user FolderTypes" }
        }
        finally {
            Remove-Item -LiteralPath $tempFile, $importFile -Force -ErrorAction SilentlyContinue
        }

        $folderTypes = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FolderTypes"
        Get-ChildItem -Path $folderTypes -ErrorAction Stop | ForEach-Object {
            $topViews = Join-Path $_.PSPath "TopViews"
            if (Test-Path $topViews) {
                Get-ChildItem -Path $topViews | ForEach-Object {
                    Set-ItemProperty -Path $_.PSPath -Name "GroupBy" -Value "" -Force
                    Set-ItemProperty -Path $_.PSPath -Name "GroupAscending" -Value 1 -Force
                    Set-ItemProperty -Path $_.PSPath -Name "SortByList" `
                        -Value "prop:+System.ItemNameDisplay" -Force
                }
            }
        }
        Write-Log "Explorer folders configured" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Explorer folders failed: $($_.Exception.Message)" "WARN"
        return $false
    }
}

function Invoke-ExplorerTweaks {
    Write-Log "Configuring Explorer" "INFO"
    $ok = Set-RegistryBatch @{
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"                          = @{
            "HideFileExt"                   = @{ Value = 0 }
            "Hidden"                        = @{ Value = 1 }
            "ShowSyncProviderNotifications" = @{ Value = 0 }
            "ShowRecentFiles"               = @{ Value = 0 }
            "ShowFrequentFiles"             = @{ Value = 0 }
            "TaskbarAl"                     = @{ Value = 1 }
            "TaskbarMn"                     = @{ Value = 0 }
            "ShowTaskViewButton"            = @{ Value = 0 }
            "ShowCopilotButton"             = @{ Value = 0 }
            "DisabledHotkeys"               = @{ Value = "hjklqmotpxynf12345678"; Type = "String" }
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" = @{
            "TaskbarEndTask" = @{ Value = 1 }
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search"                                     = @{
            "SearchboxTaskbarMode" = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"                                                      = @{
            "AllowNewsAndInterests" = @{ Value = 0 }
        }
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Explorer"                                         = @{
            "DisableSearchBoxSuggestions" = @{ Value = 1 }
        }
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"                                   = @{
            "TurnOffWindowsCopilot" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search"                                   = @{
            "AllowCortana"             = @{ Value = 0 }
            "AllowCloudSearch"         = @{ Value = 0 }
            "AllowSearchToUseLocation" = @{ Value = 1 }
            "ConnectedSearchUseWeb"    = @{ Value = 0 }
            "DisableWebSearch"         = @{ Value = 1 }
        }
    }

    if (-not (Set-RegistrySafe -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" `
                -Name "(Default)" -Value "" -Type String -PassThru)) { $ok = $false }
    if (-not (Set-ExplorerFolderDefaults)) { $ok = $false }

    $stuckRectsPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    try {
        if (-not (Test-RegistryPathBackedUp $stuckRectsPath)) { throw "taskbar registry path was not backed up" }
        $settings = (Get-ItemProperty -Path $stuckRectsPath -Name Settings -ErrorAction Stop).Settings
        if ($settings -and $settings.Length -gt 8) {
            $settings[8] = 3
            Set-ItemProperty -Path $stuckRectsPath -Name Settings -Value ([byte[]]$settings)
        }
        else { throw "taskbar auto-hide settings were missing or malformed" }
    }
    catch {
        Write-Log "Taskbar auto-hide failed: $($_.Exception.Message)" "WARN"
        $ok = $false
    }
    return $ok
}
