function New-SetupResult {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [ValidateSet("Pending", "Running", "Success", "Skipped", "Failed")]
        [string]$Status = "Pending",
        [int]$ExitCode = 0,
        [string]$Message = "",
        [bool]$RebootRequired = $false,
        [object[]]$PackageResults = @()
    )

    [PSCustomObject]@{
        Id             = $Id
        Name           = $Name
        Status         = $Status
        ExitCode       = $ExitCode
        Message        = $Message
        RebootRequired = $RebootRequired
        PackageResults = @($PackageResults)
    }
}

function Test-SetupResultSuccessful {
    param([Parameter(Mandatory)]$Result)
    @("Success", "Skipped") -contains $Result.Status
}

function Show-SetupResults {
    param([Parameter(Mandatory)][object[]]$Results, [string]$LogPath)

    Write-Host ""
    Write-Host "Setup results" -ForegroundColor White
    foreach ($result in $Results) {
        $color = switch ($result.Status) {
            "Failed" { "Red" }
            "Success" { "Green" }
            default { "Yellow" }
        }
        $detail = if ($result.Message) { " - $($result.Message)" } else { "" }
        Write-Host ("  [{0}] {1}{2}" -f $result.Status, $result.Name, $detail) -ForegroundColor $color

        if ($result.PSObject.Properties.Name -contains "PackageResults") {
            foreach ($package in @($result.PackageResults)) {
                $packageColor = if ($package.Status -eq "Failed") { "Red" } elseif ($package.Status -eq "Success") { "Green" } else { "Yellow" }
                $packageDetail = ""
                if ($package.Status -eq "Failed") {
                    $packageDetail = " (exit $($package.ExitCode), verified: $($package.Verified))"
                }
                elseif ($package.Status -eq "Skipped") {
                    $packageDetail = " (already installed)"
                }
                Write-Host ("      [{0}] {1} [{2}]{3}" -f $package.Status, $package.Name, $package.Id, $packageDetail) -ForegroundColor $packageColor

                if ($package.Status -eq "Failed") {
                    foreach ($attempt in @($package.Attempts)) {
                        Write-Host ("          attempt: {0} via {1}, exit {2}" -f $attempt.PackageId, $attempt.Source, $attempt.ExitCode) -ForegroundColor DarkRed
                    }
                }
            }
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        Write-Host "Log: $LogPath" -ForegroundColor DarkGray
    }
}
