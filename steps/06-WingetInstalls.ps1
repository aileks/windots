function Step-WingetInstalls {
    if (Test-StateCompleted "06-WingetInstalls") { return }
    Write-Log "Installing packages via winget..." "INFO"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "  winget not found, installing via Microsoft.WinGet.Client..." "INFO"
        try {
            Install-PackageProvider -Name NuGet -Force | Out-Null
            Install-Module -Name Microsoft.WinGet.Client -Force
            Repair-WinGetPackageManager -AllUsers
            $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        } catch {
            Write-Log "  Failed to install winget: $($_.Exception.Message)" "ERROR"
            return
        }
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "  winget still not found. Install winget manually and re-run." "ERROR"
        return
    }

    $appsFile = Join-Path $script:RootDir "apps.json"
    if (-not (Test-Path $appsFile)) {
        Write-Log "  apps.json not found at $appsFile, skipping app installs." "WARN"
        Set-StateCompleted "06-WingetInstalls"
        return
    }

    Write-Log "  Importing packages from apps.json..." "INFO"
    winget import -i $appsFile `
        --accept-package-agreements --accept-source-agreements `
        --ignore-unavailable --disable-interactivity --no-upgrade 2>&1 | Write-Host

    if ($LASTEXITCODE -ne 0) {
        Write-Log "  winget import returned exit code $LASTEXITCODE (some packages may be unavailable or already installed)." "WARN"
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

    Write-Log "winget import complete" "SUCCESS"
    Set-StateCompleted "06-WingetInstalls"
}
Step-WingetInstalls
