function Get-CliToolsCatalog {
    $catalogPath = Join-Path $script:RootDir "data/cli-tools.json"
    if (-not (Test-Path $catalogPath)) {
        throw "CLI tools catalog not found at $catalogPath"
    }

    Get-Content $catalogPath -Raw | ConvertFrom-Json
}

function Test-CliToolInstalled {
    param([Parameter(Mandatory)]$Tool)

    Refresh-EnvironmentPath
    $null -ne (Get-Command $Tool.command -ErrorAction SilentlyContinue)
}

function Install-ScoopCliTool {
    param([Parameter(Mandatory)]$Tool)

    if (Test-CliToolInstalled $Tool) {
        Write-Log "  $($Tool.name) is already installed" "INFO"
        return $true
    }

    if ($Tool.bucket) {
        if (-not (Ensure-ScoopBucket -Name $Tool.bucket.name -Source $Tool.bucket.source)) {
            return $false
        }
    }

    Write-Log "  Installing $($Tool.name) ($($Tool.package)) via Scoop..." "INFO"
    $output = @(& scoop install $Tool.package 2>&1)
    $exitCode = $LASTEXITCODE
    $output | Write-Host

    if ($exitCode -ne 0) {
        Write-Log "  Scoop install failed for $($Tool.package) with exit code $exitCode" "WARN"
        return $false
    }

    Write-Log "  Installed $($Tool.name)" "SUCCESS"
    return $true
}

function Invoke-CliToolsSelectionInstall {
    $catalog = Get-CliToolsCatalog
    $selected = New-Object System.Collections.Generic.List[object]

    foreach ($category in @($catalog.categories)) {
        foreach ($tool in @(Read-CatalogCategorySelection $category)) {
            $selected.Add($tool)
        }
    }

    $selectedPackages = @($selected | ForEach-Object { $_.package })
    Set-StateValue -Key "selectedCliToolPackages" -Value $selectedPackages

    if ($selected.Count -eq 0) { return $true }
    if (-not (Ensure-Scoop)) { return $false }

    Write-Log "Installing selected CLI tools..." "INFO"
    $succeeded = $true
    foreach ($tool in $selected) {
        if (-not (Install-ScoopCliTool $tool)) {
            $succeeded = $false
        }
    }

    Refresh-EnvironmentPath
    return $succeeded
}
