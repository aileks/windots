$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$script:Passed = 0

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if (-not $Condition) { throw $Message }
    $script:Passed++
}

function Assert-Equal {
    param(
        $Expected,
        $Actual,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
    $script:Passed++
}

Get-ChildItem "$root\*.ps1", "$root\lib\*.ps1", "$root\helpers\*.ps1", "$root\steps\*.ps1", "$root\personal\*.ps1", "$root\tests\*.ps1" |
    ForEach-Object {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
        Assert-Equal 0 @($errors).Count "PowerShell syntax errors in $($_.FullName)"
    }

$software = Get-Content "$root\data\software.json" -Raw | ConvertFrom-Json
$softwareKeys = @($software.categories | ForEach-Object { $_.key })
Assert-Equal $softwareKeys.Count @($softwareKeys | Select-Object -Unique).Count "Software category keys must be unique"

$softwareIds = @()
foreach ($category in @($software.categories)) {
    Assert-True ($category.items.Count -gt 0) "Software category $($category.key) must contain items"
    foreach ($item in @($category.items)) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($item.name)) "Software name is required"
        Assert-True (-not [string]::IsNullOrWhiteSpace($item.id)) "Software ID is required for $($item.name)"
        Assert-True (@("winget", "direct") -contains $item.installer) "Unsupported installer for $($item.name)"
        if ($item.installer -eq "direct") {
            Assert-True (-not [string]::IsNullOrWhiteSpace($item.url)) "Direct URL is required for $($item.name)"
            Assert-True (-not [string]::IsNullOrWhiteSpace($item.fileName)) "Direct filename is required for $($item.name)"
        }
        $softwareIds += $item.id
    }
}
Assert-Equal $softwareIds.Count @($softwareIds | Select-Object -Unique).Count "Software IDs must be unique"

$cli = Get-Content "$root\data\cli-tools.json" -Raw | ConvertFrom-Json
$cliPackages = @()
foreach ($category in @($cli.categories)) {
    Assert-True ($category.allowMultiple -eq $true) "CLI categories must allow multiple selections"
    foreach ($tool in @($category.items)) {
        Assert-True (-not [string]::IsNullOrWhiteSpace($tool.name)) "CLI tool name is required"
        Assert-True (-not [string]::IsNullOrWhiteSpace($tool.package)) "Scoop package is required for $($tool.name)"
        Assert-True (-not [string]::IsNullOrWhiteSpace($tool.command)) "Command is required for $($tool.name)"
        if ($tool.bucket) {
            Assert-True (-not [string]::IsNullOrWhiteSpace($tool.bucket.name)) "Bucket name is required for $($tool.name)"
            Assert-True (-not [string]::IsNullOrWhiteSpace($tool.bucket.source)) "Bucket source is required for $($tool.name)"
        }
        $cliPackages += $tool.package
    }
}
Assert-Equal $cliPackages.Count @($cliPackages | Select-Object -Unique).Count "CLI packages must be unique"

. "$root\lib\Prompt.ps1"
$script:Replies = New-Object System.Collections.Generic.Queue[string]
$script:Warnings = @()
function Ask-Input {
    param([string]$Question, [string]$Default = "")
    if ($script:Replies.Count -eq 0) { return $Default }
    return $script:Replies.Dequeue()
}
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    if ($Level -eq "WARN" -or $Level -eq "ERROR") { $script:Warnings += $Message }
}

$multiCategory = [PSCustomObject]@{
    name = "Test tools"
    allowMultiple = $true
    items = @(
        [PSCustomObject]@{ name = "One"; description = "first" },
        [PSCustomObject]@{ name = "Two"; description = "second" },
        [PSCustomObject]@{ name = "Three"; description = "third" }
    )
}
$script:Replies.Enqueue("1, 3 3")
$selection = @(Read-CatalogCategorySelection $multiCategory)
Assert-Equal 2 $selection.Count "Multi-select should deduplicate selections"
Assert-Equal "Three" $selection[1].name "Multi-select should preserve entered order"

$script:Replies.Enqueue("a")
$selection = @(Read-CatalogCategorySelection $multiCategory)
Assert-Equal 3 $selection.Count "All should select every multi-select item"

$script:Replies.Enqueue("invalid")
$script:Replies.Enqueue("2")
$selection = @(Read-CatalogCategorySelection $multiCategory)
Assert-Equal "Two" $selection[0].name "Invalid input should prompt again"
Assert-True ($script:Warnings.Count -gt 0) "Invalid input should produce a warning"

$script:Replies.Enqueue("")
$selection = @(Read-CatalogCategorySelection $multiCategory)
Assert-Equal 0 $selection.Count "Blank input should skip a category"

$singleCategory = [PSCustomObject]@{
    name = "Single choice"
    allowMultiple = $false
    items = $multiCategory.items
}
$script:Replies.Enqueue("1,2")
$script:Replies.Enqueue("2")
$selection = @(Read-CatalogCategorySelection $singleCategory)
Assert-Equal 1 $selection.Count "Single-select should reject multiple choices"
Assert-Equal "Two" $selection[0].name "Single-select should return the valid retry"

. "$root\helpers\CliTools.ps1"
$selectedTools = @(
    [PSCustomObject]@{ name = "One"; package = "one"; command = "one" },
    [PSCustomObject]@{ name = "Two"; package = "two"; command = "two" }
)
function Get-CliToolsCatalog {
    [PSCustomObject]@{ categories = @([PSCustomObject]@{ items = $selectedTools }) }
}
function Read-CatalogCategorySelection { param($Category) return $selectedTools }
$script:StateValues = @{}
$script:ScoopChecks = 0
$script:InstallAttempts = @()
function Set-StateValue { param([string]$Key, $Value) $script:StateValues[$Key] = $Value }
function Ensure-Scoop { $script:ScoopChecks++; return $true }
function Refresh-EnvironmentPath {}
function Install-ScoopCliTool {
    param($Tool)
    $script:InstallAttempts += $Tool.package
    return $Tool.package -ne "two"
}
$result = Invoke-CliToolsSelectionInstall
Assert-True ($result -eq $false) "CLI install should report a selected package failure"
Assert-Equal 1 $script:ScoopChecks "Scoop should be ensured once"
Assert-Equal 2 $script:InstallAttempts.Count "Every selected CLI tool should be attempted"
Assert-Equal 2 @($script:StateValues["selectedCliToolPackages"]).Count "Selected CLI packages should be saved"

$selectedTools = @()
$script:ScoopChecks = 0
$result = Invoke-CliToolsSelectionInstall
Assert-True ($result -eq $true) "Skipping CLI tools should succeed"
Assert-Equal 0 $script:ScoopChecks "Skipping CLI tools should not install Scoop"

. "$root\helpers\CliTools.ps1"
$script:BucketName = ""
$script:ScoopArguments = @()
function Test-CliToolInstalled { param($Tool) return $false }
function Ensure-ScoopBucket {
    param([string]$Name, [string]$Source)
    $script:BucketName = $Name
    return $true
}
function scoop {
    $script:ScoopArguments = @($args)
    $global:LASTEXITCODE = 0
    return "installed"
}
$lazyGit = [PSCustomObject]@{
    name = "lazygit"
    package = "lazygit"
    command = "lazygit"
    bucket = [PSCustomObject]@{ name = "extras"; source = "https://github.com/ScoopInstaller/Extras" }
}
$result = Install-ScoopCliTool $lazyGit
Assert-True ($result -eq $true) "Scoop CLI installation should report success"
Assert-Equal "extras" $script:BucketName "lazygit should ensure the Extras bucket"
Assert-Equal "install" $script:ScoopArguments[0] "Scoop should receive the install command"
Assert-Equal "lazygit" $script:ScoopArguments[1] "Scoop should install the selected package"

$script:PersonalSetupSelected = $true
$script:RootDir = $root
$script:CompletedStep = ""
$script:StateValues = @{}
$script:WslArguments = @()
function Test-StateCompleted { return $false }
function New-ConfigLink { param([string]$Source, [string]$Dest) }
function Set-StateCompleted { param([string]$StepId) $script:CompletedStep = $StepId }
function wsl {
    $script:WslArguments = @($args)
    $global:LASTEXITCODE = 0
    return "installed"
}
. "$root\personal\06-WslUbuntu.ps1"
Assert-Equal 1 $script:WslArguments.Count "WSL should receive one argument"
Assert-Equal "--install" $script:WslArguments[0] "WSL should use the bare install command"
Assert-True ($script:StateValues["rebootRequired"] -eq $true) "Successful WSL install should require reboot"
Assert-Equal "Personal.WslUbuntu" $script:CompletedStep "Successful WSL install should complete the step"

$script:CompletedStep = ""
$script:Warnings = @()
function wsl {
    $script:WslArguments = @($args)
    $global:LASTEXITCODE = 7
    return "failed"
}
Step-WslUbuntu
Assert-Equal "" $script:CompletedStep "Failed WSL install should remain incomplete"
Assert-True (($script:Warnings -join " ") -match "exit code 7") "Failed WSL install should log its exit code"

Write-Host "$script:Passed assertions passed" -ForegroundColor Green
