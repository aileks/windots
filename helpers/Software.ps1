function Refresh-EnvironmentPath {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Get-SoftwareCatalog {
    $catalogPath = Join-Path $script:RootDir "data/software.json"
    if (-not (Test-Path $catalogPath)) {
        throw "Software catalog not found at $catalogPath"
    }

    Get-Content $catalogPath -Raw | ConvertFrom-Json
}

function Get-SelectedSoftwareIds {
    $selected = Get-StateValue "selectedSoftwareIds"
    if ($null -eq $selected) { return @() }
    @($selected) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
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
        } catch {
            Write-Log "  Install detection failed: $($_.Exception.Message)" "WARN"
        }
    }

    return $false
}

function Test-SoftwareSelectedOrInstalled {
    param(
        [string[]]$PackageIds = @(),
        [string[]]$Commands = @(),
        [scriptblock]$Detector
    )

    $selected = @(Get-SelectedSoftwareIds)
    foreach ($id in $PackageIds) {
        if ($selected -contains $id) { return $true }
    }

    Test-SoftwareInstalled -Commands $Commands -Detector $Detector
}

function Ensure-WinGet {
    Refresh-EnvironmentPath
    if (Get-Command winget -ErrorAction SilentlyContinue) { return $true }

    Write-Log "winget not found, installing via Microsoft.WinGet.Client..." "INFO"
    try {
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue

        Install-Module -Name Microsoft.WinGet.Client -Force -AllowClobber

        Repair-WinGetPackageManager -AllUsers
        Refresh-EnvironmentPath
    } catch {
        Write-Log "  Failed to install winget: $($_.Exception.Message)" "ERROR"
        return $false
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Log "  winget still not found. Install winget manually and re-run." "ERROR"
        return $false
    }

    Write-Log "winget is available" "SUCCESS"
    return $true
}

function Get-InstallIdsForSoftwareItem {
    param([Parameter(Mandatory)]$Item)

    $ids = @()
    if ($Item.installer -eq "winget") {
        $ids += $Item.id
        if ($Item.dependencies) {
            $ids += @($Item.dependencies)
        }
    }
    $ids
}

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$Name,
        [string]$Source = ""
    )

    Write-Log "  Installing $Name ($PackageId) via winget..." "INFO"
    $arguments = @(
        "install",
        $PackageId,
        "--accept-package-agreements",
        "--accept-source-agreements",
        "--disable-interactivity"
    )
    if (-not [string]::IsNullOrWhiteSpace($Source)) {
        $arguments += @("--source", $Source)
    }

    & winget @arguments 2>&1 | Write-Host
    if ($LASTEXITCODE -eq 0) {
        Write-Log "  Installed $Name" "SUCCESS"
    } else {
        Write-Log "  winget install failed for $Name ($PackageId) with exit code $LASTEXITCODE" "WARN"
    }
}

function Install-DirectPackage {
    param([Parameter(Mandatory)]$Item)

    $downloadDir = Join-Path $env:TEMP "win-setup-installers"
    if (-not (Test-Path $downloadDir)) {
        New-Item -Path $downloadDir -ItemType Directory -Force | Out-Null
    }

    $installerPath = Join-Path $downloadDir $Item.fileName
    Write-Log "  Downloading $($Item.name) from $($Item.url)..." "INFO"
    try {
        Invoke-WebRequest -Uri $Item.url -OutFile $installerPath -UseBasicParsing
    } catch {
        Write-Log "  Failed to download $($Item.name): $($_.Exception.Message)" "WARN"
        return
    }

    Write-Log "  Installing $($Item.name)..." "INFO"
    try {
        $process = Start-Process -FilePath $installerPath -ArgumentList $Item.arguments -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            Write-Log "  Installed $($Item.name)" "SUCCESS"
        } else {
            Write-Log "  $($Item.name) installer returned exit code $($process.ExitCode)" "WARN"
        }
    } catch {
        Write-Log "  Failed to install $($Item.name): $($_.Exception.Message)" "WARN"
    }
}

function Install-SoftwareItem {
    param([Parameter(Mandatory)]$Item)

    switch ($Item.installer) {
        "winget" {
            foreach ($id in (Get-InstallIdsForSoftwareItem -Item $Item)) {
                $name = if ($id -eq $Item.id) { $Item.name } else { $id }
                $source = if ($id -eq $Item.id -and $Item.source) { $Item.source } else { "" }
                Install-WinGetPackage -PackageId $id -Name $name -Source $source
            }
        }
        "direct" {
            Install-DirectPackage $Item
        }
        default {
            Write-Log "  Unknown installer '$($Item.installer)' for $($Item.name); skipping." "WARN"
        }
    }
}

function Invoke-SoftwareSelectionInstall {
    if (-not (Ensure-WinGet)) { return $false }

    $catalog = Get-SoftwareCatalog
    $selected = New-Object System.Collections.Generic.List[object]

    foreach ($category in @($catalog.categories)) {
        foreach ($item in @(Read-CatalogCategorySelection $category)) {
            $selected.Add($item)
        }
    }

    $selectedIds = @($selected | ForEach-Object { $_.id })
    Set-StateValue -Key "selectedSoftwareIds" -Value $selectedIds

    if ($selected.Count -eq 0) {
        return $true
    }

    Write-Log "Installing selected software..." "INFO"
    foreach ($item in $selected) {
        Install-SoftwareItem $item
    }

    Refresh-EnvironmentPath
    return $true
}
