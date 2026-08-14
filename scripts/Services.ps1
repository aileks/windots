function Invoke-ServiceTweaks {
    Write-Log "Configuring services" "INFO"
    $targets = @{
        CscService   = "Disabled"
        DiagTrack    = "Disabled"
        MapsBroker   = "Manual"
        StorSvc      = "Manual"
        SharedAccess = "Disabled"
        WerSvc       = "Disabled"
    }
    $original = Get-StateValue "serviceStartupOriginal"
    $originalMap = @{}
    if ($original -is [hashtable]) {
        foreach ($key in $original.Keys) { $originalMap[$key] = $original[$key] }
    }
    elseif ($null -ne $original) {
        $original.PSObject.Properties | ForEach-Object { $originalMap[$_.Name] = $_.Value }
    }

    $ok = $true
    foreach ($name in $targets.Keys) {
        $service = Get-CimInstance Win32_Service -Filter "Name='$name'" -ErrorAction SilentlyContinue
        if ($null -eq $service) {
            Write-Log "Service unavailable: $name" "INFO"
            continue
        }
        if (-not $originalMap.ContainsKey($name)) { $originalMap[$name] = $service.StartMode }
        try {
            if ($targets[$name] -eq "Disabled") {
                Stop-Service -Name $name -Force -ErrorAction SilentlyContinue
            }
            Set-Service -Name $name -StartupType $targets[$name] -ErrorAction Stop
            Write-Log "Service configured: $name" "INFO"
        }
        catch {
            Write-Log "Service failed: $name - $($_.Exception.Message)" "WARN"
            $ok = $false
        }
    }
    Set-StateValue "serviceStartupOriginal" $originalMap

    try {
        $memoryKb = [uint64]((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1KB)
        if (-not (Set-RegistrySafe -Path "HKLM:\SYSTEM\CurrentControlSet\Control" `
                    -Name "SvcHostSplitThresholdInKB" -Value $memoryKb -Type QWord -PassThru)) { $ok = $false }
    }
    catch {
        Write-Log "Service threshold failed: $($_.Exception.Message)" "WARN"
        $ok = $false
    }
    return $ok
}
