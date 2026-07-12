function Ensure-Scoop {
    Refresh-EnvironmentPath
    if (Get-Command scoop -ErrorAction SilentlyContinue) { return $true }

    Write-Log "Scoop not found, installing Scoop..." "INFO"
    $installScript = Join-Path $env:TEMP "install-scoop.ps1"
    try {
        Invoke-WebRequest -Uri "https://get.scoop.sh" -OutFile $installScript -UseBasicParsing
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installScript -RunAsAdmin 2>&1 | Write-Host
        Refresh-EnvironmentPath
    } catch {
        Write-Log "  Failed to install Scoop: $($_.Exception.Message)" "ERROR"
        return $false
    }

    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Log "  Scoop still not found. Install Scoop manually and re-run." "ERROR"
        return $false
    }

    Write-Log "Scoop is available" "SUCCESS"
    return $true
}

function Ensure-ScoopBucket {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$Source = ""
    )

    $buckets = & scoop bucket list 2>$null
    if ($LASTEXITCODE -eq 0 -and ($buckets | Select-String -SimpleMatch $Name)) {
        return $true
    }

    Write-Log "Adding Scoop bucket $Name..." "INFO"
    $arguments = @("bucket", "add", $Name)
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $arguments += $Source
    }

    & scoop @arguments 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Log "  Failed to add Scoop bucket $Name" "ERROR"
        return $false
    }

    return $true
}
