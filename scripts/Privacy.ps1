function Invoke-PrivacyTweaks {
    Write-Log "Configuring privacy" "INFO"
    $ok = Set-RegistryBatch @{
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"                = @{
            "AllowTelemetry"                          = @{ Value = 0 }
            "DisableTelemetryOptInSettingsUx"         = @{ Value = 1 }
            "DisableTelemetryOptInChangeNotification" = @{ Value = 1 }
            "LimitDiagnosticLogCollection"            = @{ Value = 1 }
            "LimitDumpCollection"                     = @{ Value = 1 }
            "DoNotShowFeedbackNotifications"          = @{ Value = 1 }
            "AllowDeviceNameInTelemetry"              = @{ Value = 0 }
            "AllowExperimentation"                    = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection" = @{
            "AllowTelemetry" = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"               = @{
            "DisabledByGroupPolicy" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat"                     = @{
            "AITEnable"        = @{ Value = 0 }
            "DisableInventory" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\SQMClient\Windows"                     = @{
            "CEIPEnable" = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Error Reporting"       = @{
            "Disabled" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"          = @{
            "DODownloadMode" = @{ Value = 0 }
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\AdvertisingInfo"         = @{
            "Enabled" = @{ Value = 0 }
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy"                 = @{
            "TailoredExperiencesWithDiagnosticDataEnabled" = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"                  = @{
            "DisableConsumerAccountStateContent" = @{ Value = 1 }
            "DisableCloudOptimizedContent"       = @{ Value = 1 }
            "DisableWindowsConsumerFeatures"     = @{ Value = 1 }
            "DisableSoftLanding"                 = @{ Value = 1 }
        }
        "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"                  = @{
            "DisableTailoredExperiencesWithDiagnosticData" = @{ Value = 1 }
        }
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"  = @{
            "ContentDeliveryAllowed"          = @{ Value = 0 }
            "OemPreInstalledAppsEnabled"      = @{ Value = 0 }
            "PreInstalledAppsEnabled"         = @{ Value = 0 }
            "SilentInstalledAppsEnabled"      = @{ Value = 0 }
            "SoftLandingEnabled"              = @{ Value = 0 }
            "SubscribedContent-338388Enabled" = @{ Value = 0 }
            "SubscribedContent-353694Enabled" = @{ Value = 0 }
            "SubscribedContent-353696Enabled" = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"                        = @{
            "EnableActivityFeed"        = @{ Value = 0 }
            "PublishUserActivities"     = @{ Value = 0 }
            "UploadUserActivities"      = @{ Value = 0 }
            "AllowCrossDeviceClipboard" = @{ Value = 0 }
        }
        "HKCU:\SOFTWARE\Microsoft\Clipboard"                                      = @{
            "EnableClipboardHistory" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization"                  = @{
            "AllowInputPersonalization" = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors"            = @{
            # Keep Windows location services available for maps, weather, and
            # other apps while retaining the unrelated privacy policies.
            "DisableWindowsLocationProvider" = @{ Value = 0 }
        }
        "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"                                     = @{
            "NumberOfSIUFInPeriod" = @{ Value = 0 }
        }
        "HKCU:\SOFTWARE\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy"    = @{
            "HasAccepted" = @{ Value = 0 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"                     = @{
            "AllowRecallEnablement" = @{ Value = 0 }
            "DisableAIDataAnalysis" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"       = @{
            "SettingsPageVisibility" = @{ Value = "hide:aicomponents"; Type = "String" }
        }
        "HKLM:\SOFTWARE\Policies\WindowsNotepad"                                  = @{
            "DisableAIFeatures" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"                 = @{
            "ExcludeWUDriversInQualityUpdate" = @{ Value = 1 }
        }
        "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"                      = @{
            "DisableFileSyncNGSC" = @{ Value = 1 }
        }
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"                  = @{
            "DisableWpbtExecution" = @{ Value = 1 }
        }
        "HKCU:\Software\Microsoft\Input\TIPC"                                     = @{
            "Enabled" = @{ Value = 0 }
        }
        "HKCU:\Software\Microsoft\InputPersonalization"                           = @{
            "RestrictImplicitInkCollection"  = @{ Value = 1 }
            "RestrictImplicitTextCollection" = @{ Value = 1 }
        }
        "HKCU:\Software\Microsoft\InputPersonalization\TrainedDataStore"          = @{
            "HarvestContacts" = @{ Value = 0 }
        }
        "HKCU:\Software\Microsoft\Personalization\Settings"                       = @{
            "AcceptedPrivacyPolicy" = @{ Value = 0 }
        }
    }

    try {
        Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction Stop
    }
    catch {
        Write-Log "Defender samples failed: $($_.Exception.Message)" "WARN"
    }
    [Environment]::SetEnvironmentVariable("POWERSHELL_TELEMETRY_OPTOUT", "1", "Machine")
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Siuf\Rules" `
        -Name "PeriodInNanoSeconds" -ErrorAction SilentlyContinue

    if (Get-Command Clear-WindowsDiagnosticData -ErrorAction SilentlyContinue) {
        try { Clear-WindowsDiagnosticData | Out-Null } catch { Write-Log "Diagnostics cleanup failed: $($_.Exception.Message)" "WARN" }
    }

    return $ok
}
