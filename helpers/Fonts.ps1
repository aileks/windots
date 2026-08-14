function Get-FontCatalog {
    $catalogPath = Join-Path $script:RootDir "data/fonts.json"
    if (-not (Test-Path $catalogPath)) {
        throw "Font catalog not found at $catalogPath"
    }

    Get-Content $catalogPath -Raw | ConvertFrom-Json
}

function Get-SelectedNerdFontMonoFace {
    $face = Get-StateValue "selectedNerdFontMonoFace"
    if ([string]::IsNullOrWhiteSpace($face)) { return "" }
    $face
}

function Publish-FontChange {
    if (-not ("WindowsSetupScriptFontChange" -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WindowsSetupScriptFontChange {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr window, uint message, UIntPtr wParam, IntPtr lParam,
        uint flags, uint timeout, out UIntPtr result);
}
'@
    }

    $result = [UIntPtr]::Zero
    [void][WindowsSetupScriptFontChange]::SendMessageTimeout(
        [IntPtr]0xffff, 0x001D, [UIntPtr]::Zero, [IntPtr]::Zero, 2, 5000, [ref]$result)
}

function Ensure-Scoop {
    Refresh-EnvironmentPath
    if (Get-Command "scoop" -ErrorAction SilentlyContinue) { return $true }

    Write-Log "Installing Scoop" "INFO"
    $tempDir = Join-Path $env:TEMP "windows-setup-script-scoop-$([guid]::NewGuid())"
    $installerPath = Join-Path $tempDir "install.ps1"
    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $installerPath -UseBasicParsing
        $result = Invoke-NativeCommand -FilePath "powershell.exe" -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $installerPath, "-RunAsAdmin"
        )
        if ($result.ExitCode -ne 0) {
            Write-Log "Scoop failed: exit $($result.ExitCode)" "ERROR"
            return $false
        }
        Refresh-EnvironmentPath
    }
    catch {
        Write-Log "Scoop failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }

    if (-not (Get-Command "scoop" -ErrorAction SilentlyContinue)) {
        Write-Log "Scoop unavailable after install" "ERROR"
        return $false
    }
    return $true
}

function Ensure-ScoopBucket {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Source
    )

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Log "Installing Scoop Git" "INFO"
        $gitResult = Invoke-NativeCommand -FilePath "scoop" -ArgumentList @("install", "git")
        if ($gitResult.ExitCode -ne 0) {
            Write-Log "Scoop Git failed: exit $($gitResult.ExitCode)" "ERROR"
            return $false
        }
        Refresh-EnvironmentPath
    }

    $scoopRoot = if ([string]::IsNullOrWhiteSpace($env:SCOOP)) {
        Join-Path $env:USERPROFILE "scoop"
    }
    else {
        $env:SCOOP
    }
    $bucketPath = Join-Path $scoopRoot "buckets\$Name"
    if (Test-Path -LiteralPath $bucketPath -PathType Container) {
        Write-Log "Scoop bucket exists: $Name" "INFO"
        return $true
    }

    $listResult = Invoke-NativeCommand -FilePath "scoop" -ArgumentList @("bucket", "list")
    $escapedName = [regex]::Escape($Name)
    if ($listResult.ExitCode -eq 0 -and
        (@($listResult.Output) | Where-Object {
            $_ -match "^\s*$escapedName(?:\s|$)" -or
            $_ -match "(?:^|[{;]\s*)Name\s*=\s*$escapedName(?:[;}\s]|$)"
        })) {
        Write-Log "Scoop bucket exists: $Name" "INFO"
        return $true
    }

    Write-Log "Adding Scoop bucket: $Name" "INFO"
    $addResult = Invoke-NativeCommand -FilePath "scoop" -ArgumentList @(
        "bucket", "add", $Name, $Source
    )
    if ($addResult.ExitCode -ne 0) {
        if (Test-Path -LiteralPath $bucketPath -PathType Container) {
            Write-Log "Scoop bucket exists: $Name" "INFO"
            return $true
        }
        Write-Log "Scoop bucket failed: $Name - exit $($addResult.ExitCode)" "ERROR"
        return $false
    }
    return $true
}

function Install-ScoopNerdFont {
    param([Parameter(Mandatory)]$Font)

    $fontFile = Join-Path "$env:LOCALAPPDATA\Microsoft\Windows\Fonts" $Font.installedFile
    $registryName = "$([IO.Path]::GetFileNameWithoutExtension($Font.installedFile)) (TrueType)"
    $registeredPath = (Get-RegistryValueState `
            -Path "HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
            -Name $registryName).Value
    if ((Test-Path -LiteralPath $fontFile) -and -not [string]::IsNullOrWhiteSpace($registeredPath)) {
        Write-Log "Font exists: $($Font.name)" "INFO"
        return $true
    }

    Write-Log "Installing font: $($Font.name)" "INFO"
    $result = Invoke-NativeCommand -FilePath "scoop" -ArgumentList @("install", $Font.package)
    if ($result.ExitCode -ne 0) {
        Write-Log "Font failed: $($Font.name) - exit $($result.ExitCode)" "ERROR"
        return $false
    }
    Write-Log "Font installed: $($Font.name)" "SUCCESS"
    return $true
}

function Invoke-NerdFontSetup {
    $catalog = Get-FontCatalog
    $fonts = @($catalog.fonts)
    if ($fonts.Count -eq 0) {
        Write-Log "Font catalog empty" "ERROR"
        return $false
    }

    $terminalFonts = @($fonts | Where-Object { $_.role -eq "terminal" })
    if ($terminalFonts.Count -ne 1) {
        Write-Log "Terminal font invalid" "ERROR"
        return $false
    }

    if (-not (Ensure-Scoop)) { return $false }
    if (-not (Ensure-ScoopBucket -Name $catalog.bucket.name -Source $catalog.bucket.source)) {
        return $false
    }

    $allSucceeded = $true
    $fontsChanged = $false

    foreach ($font in $fonts) {
        if (Install-ScoopNerdFont -Font $font) {
            $fontsChanged = $true
            if ($font.role -eq "terminal") {
                Set-StateValue -Key "selectedNerdFontMonoFace" -Value $font.monoFace
            }
        }
        else {
            $allSucceeded = $false
        }
    }

    if ($fontsChanged) { Publish-FontChange }
    return $allSucceeded
}
