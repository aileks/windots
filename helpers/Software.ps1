function Refresh-EnvironmentPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-WinGetAgreementArguments {
    param([switch]$IncludePackage)

    $arguments = @("--accept-source-agreements", "--disable-interactivity")
    if ($IncludePackage) {
        $arguments = @("--accept-package-agreements") + $arguments
    }
    return $arguments
}

function Get-SoftwareCatalog {
    $catalogPath = Join-Path $script:RootDir "data/software.json"
    if (-not (Test-Path $catalogPath)) {
        throw "Software catalog not found at $catalogPath"
    }

    Get-Content $catalogPath -Raw | ConvertFrom-Json
}

function Test-SoftwareInstalled {
    param(
        [string[]]$Commands = @(),
        [scriptblock]$Detector
    )

    Refresh-EnvironmentPath
    foreach ($command in $Commands) {
        if (Get-Command $command -ErrorAction SilentlyContinue) { return $true }
    }

    if ($Detector) {
        try {
            if (& $Detector) { return $true }
        }
        catch {
            Write-Log "Detection failed: $($_.Exception.Message)" "WARN"
        }
    }

    return $false
}

function Ensure-WinGet {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor `
        [Net.SecurityProtocolType]::Tls12
    Refresh-EnvironmentPath
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $sourceResult = Invoke-NativeCommand -FilePath "winget" -ArgumentList @("source", "update") -NoConsole
        if ($sourceResult.ExitCode -eq 0) { return $true }
        Write-Log "Repairing WinGet" "INFO"
    }
    else {
        Write-Log "Installing WinGet" "INFO"
    }

    try {
        Install-PackageProvider -Name NuGet -Force | Out-Null
        $repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
        $originalPolicy = if ($repository) { $repository.InstallationPolicy } else { "Untrusted" }
        try {
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction Stop
            Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber
            Repair-WinGetPackageManager -AllUsers | Out-Null
        }
        finally {
            Set-PSRepository -Name PSGallery -InstallationPolicy $originalPolicy -ErrorAction SilentlyContinue
        }
        Refresh-EnvironmentPath
    }
    catch {
        Write-Log "WinGet failed: $($_.Exception.Message)" "ERROR"
        return $false
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "WinGet unavailable after install" "ERROR"
        return $false
    }

    $null = Invoke-NativeCommand -FilePath "winget" -ArgumentList @("source", "reset", "--force") -NoConsole
    $sourceResult = Invoke-NativeCommand -FilePath "winget" -ArgumentList @("source", "update") -NoConsole
    if ($sourceResult.ExitCode -ne 0) {
        Write-Log "WinGet sources failed" "ERROR"
        return $false
    }
    Write-Log "WinGet ready" "SUCCESS"
    return $true
}

function Test-WinGetPackageId {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [string]$Source = ""
    )

    $arguments = @("show", "--id", $PackageId, "--exact") + @(Get-WinGetAgreementArguments)
    if (-not [string]::IsNullOrWhiteSpace($Source)) { $arguments += @("--source", $Source) }
    $result = Invoke-NativeCommand -FilePath "winget" -ArgumentList $arguments -OutputPrefix "    " -NoConsole
    return $result.ExitCode -eq 0
}

function Test-WinGetPackageInstalled {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [string]$Source = ""
    )

    $arguments = @("list", "--id", $PackageId, "--exact") + @(Get-WinGetAgreementArguments)
    if (-not [string]::IsNullOrWhiteSpace($Source)) { $arguments += @("--source", $Source) }
    $result = Invoke-NativeCommand -FilePath "winget" -ArgumentList $arguments -OutputPrefix "    " -NoConsole
    return $result.ExitCode -eq 0
}

function Test-BitwardenInstalled {
    $wingetRegistered = (Test-WinGetPackageInstalled -PackageId "Bitwarden.Bitwarden")
    if (-not $wingetRegistered) {
        $wingetRegistered = Test-WinGetPackageInstalled -PackageId "9PJSDV0VPK04" -Source "msstore"
    }

    $userRegistered = $false
    foreach ($uninstallRoot in @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )) {
        $registration = Get-ItemProperty -Path $uninstallRoot -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "Bitwarden*" } |
            Select-Object -First 1
        if ($null -ne $registration) {
            $userRegistered = $true
            break
        }
    }

    if (-not $userRegistered -and (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue)) {
        $appxRegistration = Get-AppxPackage -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*Bitwarden*" -or $_.PackageFamilyName -like "*Bitwarden*" } |
            Select-Object -First 1
        $userRegistered = $null -ne $appxRegistration
    }

    if (-not $wingetRegistered) {
        Write-Log "Bitwarden missing from WinGet" "WARN"
    }
    if (-not $userRegistered) {
        Write-Log "Bitwarden registration missing" "WARN"
    }
    return $wingetRegistered -and $userRegistered
}

function New-SoftwarePackageResult {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$Name
    )

    [PSCustomObject]@{
        Id           = $PackageId
        Name         = $Name
        Status       = "Pending"
        Attempts     = @()
        ExitCode     = 0
        Verified     = $false
        Verification = "pending"
    }
}

function Install-WinGetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$Name,
        [string]$Source = "",
        [string]$Scope = "",
        [string]$FallbackId = "",
        [string]$FallbackSource = "",
        [switch]$PassThru
    )

    $packageResult = New-SoftwarePackageResult -PackageId $PackageId -Name $Name
    $isBitwarden = $PackageId -eq "Bitwarden.Bitwarden"

    $alreadyInstalled = if ($isBitwarden) {
        Test-BitwardenInstalled
    }
    else {
        Test-WinGetPackageInstalled -PackageId $PackageId -Source $Source
    }
    Write-Log "Checking package: $Name" "INFO"
    $primaryValid = Test-WinGetPackageId -PackageId $PackageId -Source $Source
    if ($alreadyInstalled) {
        $packageResult.Status = "Skipped"
        $packageResult.Verified = $true
        $packageResult.Verification = "already installed and verified"
        if (-not $primaryValid) {
            Write-Log "Package source unverified: $Name" "WARN"
        }
        Write-Log "Package exists: $Name" "INFO"
        if ($PassThru) { return $packageResult }
        return $true
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    $candidates.Add([PSCustomObject]@{ Id = $PackageId; Source = $Source; Scope = $Scope; Valid = $primaryValid })
    if (-not [string]::IsNullOrWhiteSpace($FallbackId)) {
        Write-Log "Checking fallback: $Name" "INFO"
        $fallbackValid = Test-WinGetPackageId -PackageId $FallbackId -Source $FallbackSource
        $candidates.Add([PSCustomObject]@{ Id = $FallbackId; Source = $FallbackSource; Scope = ""; Valid = $fallbackValid })
    }

    foreach ($candidate in $candidates) {
        if (-not $candidate.Valid) {
            $packageResult.Attempts += [PSCustomObject]@{
                PackageId = $candidate.Id
                Source    = if ($candidate.Source) { $candidate.Source } else { "winget" }
                Scope     = $candidate.Scope
                ExitCode  = 2
                Status    = "InvalidPackageId"
            }
            Write-Log "Package unavailable: $($candidate.Id)" "WARN"
            continue
        }

        $sourceLabel = if ($candidate.Source) { $candidate.Source } else { "winget" }
        Write-Log "Installing package: $Name" "INFO"
        $arguments = @(
            "install", "--id", $candidate.Id, "--exact"
        )
        $arguments += @(Get-WinGetAgreementArguments -IncludePackage)
        if (-not [string]::IsNullOrWhiteSpace($candidate.Source)) {
            $arguments += @("--source", $candidate.Source)
        }
        if (-not [string]::IsNullOrWhiteSpace($candidate.Scope)) {
            $arguments += @("--scope", $candidate.Scope)
        }

        $nativeResult = Invoke-NativeCommand -FilePath "winget" -ArgumentList $arguments -OutputPrefix "    "
        $attemptStatus = if ($nativeResult.ExitCode -eq 0) { "Completed" } else { "Failed" }
        $packageResult.Attempts += [PSCustomObject]@{
            PackageId = $candidate.Id
            Source    = $sourceLabel
            Scope     = $candidate.Scope
            ExitCode  = $nativeResult.ExitCode
            Status    = $attemptStatus
        }
        $packageResult.ExitCode = $nativeResult.ExitCode

        if ($nativeResult.ExitCode -ne 0) {
            Write-Log "Package failed: $Name - exit $($nativeResult.ExitCode)" "WARN"
            continue
        }

        $verified = if ($isBitwarden) {
            Test-BitwardenInstalled
        }
        else {
            Test-WinGetPackageInstalled -PackageId $candidate.Id -Source $candidate.Source
        }
        if ($verified) {
            $packageResult.Status = "Success"
            $packageResult.Verified = $true
            $packageResult.Verification = "winget and installation registration verified"
            Write-Log "Package installed: $Name" "SUCCESS"
            if ($PassThru) { return $packageResult }
            return $true
        }

        $packageResult.Verification = "installer exited successfully, but verification failed"
        $packageResult.ExitCode = 1
        Write-Log "Package unverified: $Name" "WARN"
    }

    $packageResult.Status = "Failed"
    if ($packageResult.Attempts.Count -eq 0) { $packageResult.ExitCode = 2 }
    if ($packageResult.Verification -eq "pending") { $packageResult.Verification = "not installed" }
    Write-Log "Package failed: $Name" "ERROR"
    if ($PassThru) { return $packageResult }
    return $false
}

function Test-FastmailInstalled {
    foreach ($root in @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )) {
        if (Get-ItemProperty -Path $root -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like "Fastmail*" } | Select-Object -First 1) {
            return $true
        }
    }
    return $false
}

function Install-Fastmail {
    param([Parameter(Mandatory)]$Item)
    $result = New-SoftwarePackageResult -PackageId $Item.id -Name $Item.name
    if (Test-FastmailInstalled) {
        $result.Status = "Skipped"
        $result.Verified = $true
        $result.Verification = "already installed and verified"
        return $result
    }

    $tempDir = Join-Path $env:TEMP "windows-setup-script-fastmail-$([guid]::NewGuid())"
    $installer = Join-Path $tempDir "Fastmail-Setup.exe"
    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Write-Log "Downloading Fastmail" "INFO"
        Invoke-WebRequest -Uri $Item.url -OutFile $installer -UseBasicParsing
        $signature = Get-AuthenticodeSignature -FilePath $installer
        if ($signature.Status -ne "Valid" -or
            $null -eq $signature.SignerCertificate -or
            $signature.SignerCertificate.Subject -notmatch "Fastmail Pty Ltd") {
            throw "Fastmail installer signature is not valid for Fastmail Pty Ltd"
        }
        $native = Invoke-NativeCommand -FilePath $installer -ArgumentList @("/S")
        $result.Attempts += [PSCustomObject]@{
            PackageId = $Item.id; Source = $Item.url; Scope = "machine"
            ExitCode = $native.ExitCode; Status = if ($native.ExitCode -eq 0) { "Completed" } else { "Failed" }
        }
        $result.ExitCode = $native.ExitCode
        if ($native.ExitCode -ne 0 -or -not (Test-FastmailInstalled)) {
            throw "Fastmail installation verification failed"
        }
        $result.Status = "Success"
        $result.Verified = $true
        $result.Verification = "signature and installation registration verified"
        Write-Log "Fastmail installed" "SUCCESS"
    }
    catch {
        $result.Status = "Failed"
        $result.ExitCode = if ($result.ExitCode) { $result.ExitCode } else { 1 }
        $result.Verification = $_.Exception.Message
        Write-Log "Fastmail failed: $($_.Exception.Message)" "ERROR"
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
    }
    return $result
}

function Invoke-SoftwareInstall {
    $catalog = Get-SoftwareCatalog
    $selected = @($catalog.packages)
    $packageResults = New-Object System.Collections.Generic.List[object]

    if (Ensure-WinGet) {
        Write-Log "Installing software" "INFO"
        foreach ($item in $selected) {
            $result = Install-WinGetPackage -PackageId $item.id -Name $item.name -Source $item.source `
                -Scope $item.scope -FallbackId $item.fallbackId -FallbackSource $item.fallbackSource -PassThru
            $packageResults.Add($result)
        }
    }
    else {
        foreach ($item in $selected) {
            $failedResult = New-SoftwarePackageResult -PackageId $item.id -Name $item.name
            $failedResult.Status = "Failed"
            $failedResult.ExitCode = 1
            $failedResult.Verification = "winget unavailable"
            $packageResults.Add($failedResult)
        }
    }
    foreach ($item in @($catalog.direct)) {
        $packageResults.Add((Install-Fastmail -Item $item))
    }

    # Windows PowerShell 5.1 can throw "Argument types do not match" when an
    # array subexpression enumerates a generic List[object]. ToArray() avoids
    # the dynamic binder path and gives state/result handling a real object[].
    $script:LastSoftwarePackageResults = $packageResults.ToArray()
    Set-StateValue -Key "softwarePackageResults" -Value @($script:LastSoftwarePackageResults)
    Refresh-EnvironmentPath
    return @($script:LastSoftwarePackageResults | Where-Object { $_.Status -eq "Failed" }).Count -eq 0
}
