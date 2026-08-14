$script:StateFile = ""
$script:State = @{}

function Load-State {
    param([string]$Path)
    $script:StateFile = $Path

    if (Test-Path $Path) {
        try {
            $json = Get-Content $Path -Raw | ConvertFrom-Json
            $script:State = @{}
            $json.PSObject.Properties | ForEach-Object {
                $script:State[$_.Name] = $_.Value
            }
        }
        catch {
            $corruptPath = "$Path.corrupt-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -LiteralPath $Path -Destination $corruptPath -Force
            $script:State = @{}
        }
    }
    else {
        $dir = Split-Path $Path -Parent
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $script:State = @{}
    }

    $script:State["version"] = 4
    if (-not $script:State.ContainsKey("completed")) { $script:State["completed"] = @() }
    if (-not $script:State.ContainsKey("results")) { $script:State["results"] = @{} }
    if (-not $script:State.ContainsKey("resumeAfterReboot")) { $script:State["resumeAfterReboot"] = $false }
    if (-not $script:State.ContainsKey("safetyMilestones")) { $script:State["safetyMilestones"] = @{} }
    $script:State
}

function Save-State {
    $obj = [PSCustomObject]$script:State
    $tempPath = "$script:StateFile.tmp"
    $obj | ConvertTo-Json -Depth 10 | Set-Content $tempPath -Encoding UTF8
    if (Test-Path -LiteralPath $script:StateFile) {
        $backupPath = "$script:StateFile.replace"
        try {
            [System.IO.File]::Replace($tempPath, $script:StateFile, $backupPath)
        }
        finally {
            if (Test-Path -LiteralPath $backupPath) { Remove-Item -LiteralPath $backupPath -Force }
        }
    }
    else {
        [System.IO.File]::Move($tempPath, $script:StateFile)
    }
}

function Test-StateCompleted {
    param([string]$StepId)
    $list = $script:State["completed"]
    if ($null -eq $list) { return $false }
    $list -contains $StepId
}

function Clear-StateCompleted {
    $script:State["completed"] = @()
    $script:State["results"] = @{}
    Save-State
}

function Set-StateResult {
    param([Parameter(Mandatory)]$Result)

    $results = @{}
    $existing = $script:State["results"]
    if ($existing -is [hashtable]) {
        $results = $existing
    }
    elseif ($null -ne $existing) {
        $existing.PSObject.Properties | ForEach-Object { $results[$_.Name] = $_.Value }
    }

    $packageResults = if ($Result.PSObject.Properties.Name -contains "PackageResults") {
        @($Result.PackageResults)
    }
    else {
        @()
    }

    $results[$Result.Id] = [PSCustomObject]@{
        status         = $Result.Status
        exitCode       = $Result.ExitCode
        message        = $Result.Message
        completedAt    = (Get-Date).ToString("o")
        rebootRequired = $Result.RebootRequired
        packageResults = $packageResults
    }
    $script:State["results"] = $results

    $list = @($script:State["completed"])
    if (Test-SetupResultSuccessful $Result) {
        if ($list -notcontains $Result.Id) {
            $script:State["completed"] = @($list + $Result.Id)
        }
    }
    else {
        $script:State["completed"] = @($list | Where-Object { $_ -ne $Result.Id })
    }
    Save-State
}

function Get-StateValue {
    param([string]$Key)
    $script:State[$Key]
}

function Set-StateValue {
    param([string]$Key, $Value)
    $script:State[$Key] = $Value
    Save-State
}

function Remove-StateValue {
    param([Parameter(Mandatory)][string]$Key)
    if ($script:State.ContainsKey($Key)) {
        $script:State.Remove($Key)
        Save-State
    }
}
