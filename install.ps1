param()

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor `
    [Net.SecurityProtocolType]::Tls12

$repositoryUrl = "https://github.com/aileks/windots.git"
$stateRoot = Join-Path $env:USERPROFILE ".dotfiles-state"
$sourcePath = Join-Path $env:USERPROFILE ".dotfiles"
$stagingPath = Join-Path $stateRoot ".source-new-$([guid]::NewGuid())"
$backupPath = $null

function Refresh-BootstrapPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

function Ensure-BootstrapGit {
    Refresh-BootstrapPath
    if (Get-Command git -ErrorAction SilentlyContinue) { return }

    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "Git is required, and WinGet is unavailable to install it"
    }

    Write-Host "Installing Git" -ForegroundColor Cyan
    & $winget.Source install --id Git.Git --exact --source winget `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    if ($LASTEXITCODE -ne 0) {
        throw "Git installation failed with code $LASTEXITCODE"
    }
    Refresh-BootstrapPath
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Git is unavailable after installation"
    }
}

function Test-SetupSource {
    param([Parameter(Mandatory)][string]$Path)

    foreach ($requiredPath in @(".git", "configs", "data", "helpers", "lib", "scripts", "setup.ps1")) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $requiredPath))) {
            throw "Windows setup script source is missing $requiredPath"
        }
    }
}

try {
    Ensure-BootstrapGit
    if (-not (Test-Path -LiteralPath $stateRoot)) {
        New-Item -Path $stateRoot -ItemType Directory -Force | Out-Null
    }

    $sourceIsRepository = (Test-Path -LiteralPath $sourcePath -PathType Container) -and
        (Test-Path -LiteralPath (Join-Path $sourcePath ".git"))
    if ($sourceIsRepository) {
        Write-Host "Using existing setup repository" -ForegroundColor Cyan
        Test-SetupSource -Path $sourcePath
    } else {
        Write-Host "Cloning setup" -ForegroundColor Cyan
        & git clone --depth 1 --branch main --single-branch $repositoryUrl $stagingPath
        if ($LASTEXITCODE -ne 0) {
            throw "Git clone failed with code $LASTEXITCODE"
        }
        Test-SetupSource -Path $stagingPath

        if (Test-Path -LiteralPath $sourcePath) {
            $backupPath = Join-Path $stateRoot "source.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss-fff')"
            Move-Item -LiteralPath $sourcePath -Destination $backupPath
        }

        try {
            Move-Item -LiteralPath $stagingPath -Destination $sourcePath
        } catch {
            if ($backupPath -and -not (Test-Path -LiteralPath $sourcePath) -and (Test-Path -LiteralPath $backupPath)) {
                Move-Item -LiteralPath $backupPath -Destination $sourcePath
            }
            throw
        }
    }

    $setupPath = Join-Path $sourcePath "setup.ps1"
    Write-Host "Setup ready" -ForegroundColor Green
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupPath
    if ($LASTEXITCODE -ne 0) {
        throw "setup.ps1 exited with code $LASTEXITCODE"
    }
} finally {
    if (Test-Path -LiteralPath $stagingPath) {
        Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
}
