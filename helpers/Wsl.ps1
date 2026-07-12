$script:WslDistro = "Ubuntu"
$script:RepositoryUrl = "https://codeberg.org/aileks/win-setup.git"
$script:NpipeRelayVersion = "1.11.4"
$script:NpipeRelaySha256 = "cea82cf5c9c22a28bef8075750acb7958f766393baebff4597cf21442f71c4b3"

function Test-WslPlatformEnabled {
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $null = @(& wsl.exe --list --quiet 2>$null)
        return $LASTEXITCODE -eq 0
    } catch {
        Write-Log "Unable to run WSL: $($_.Exception.Message)" "ERROR"
        return $false
    } finally {
        $ErrorActionPreference = $previousPreference
    }
}

function Enable-WslPlatformAndReboot {
    Register-ResumeAfterReboot -ScriptPath $script:SetupScript
    Write-Log "Installing WSL and Ubuntu..." "INFO"
    $output = @(& wsl.exe --install 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Log "  $line" "INFO" }
    if ($exitCode -ne 0) {
        Clear-ResumeAfterReboot
        Write-Log "WSL enablement failed with exit code $exitCode" "ERROR"
        return $false
    }

    Set-StateValue "rebootRequired" $true
    Write-Log "WSL enabled. Rebooting now." "SUCCESS"
    Restart-Computer
    return $true
}

function Get-WslDistroNames {
    $output = @(& wsl.exe --list --quiet 2>$null)
    @($output | ForEach-Object { ([string]$_).Replace([string][char]0, "").Trim() } | Where-Object { $_ })
}

function Test-WslDistroInstalled {
    @(Get-WslDistroNames) -contains $script:WslDistro
}

function Install-WslDistro {
    if (Test-WslDistroInstalled) { return $true }

    Write-Log "Installing $script:WslDistro..." "INFO"
    $output = @(& wsl.exe --install --distribution $script:WslDistro --no-launch 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Log "  $line" "INFO" }
    if ($exitCode -ne 0) {
        Write-Log "Store installation failed with exit code $exitCode; retrying direct download" "WARN"
        $output = @(& wsl.exe --install --distribution $script:WslDistro --no-launch --web-download 2>&1)
        $exitCode = $LASTEXITCODE
        foreach ($line in $output) { Write-Log "  $line" "INFO" }
        if ($exitCode -ne 0) {
            Write-Log "$script:WslDistro installation failed with exit code $exitCode" "ERROR"
            return $false
        }
    }
    return $true
}

function Get-WslDefaultUser {
    if (-not (Test-WslDistroInstalled)) { return "" }
    $output = @(& wsl.exe --distribution $script:WslDistro --exec sh -lc "id -un" 2>$null)
    if ($LASTEXITCODE -ne 0) { return "" }
    $firstLine = ($output | Select-Object -First 1) -as [string]
    if ([string]::IsNullOrWhiteSpace($firstLine)) { return "" }
    $name = $firstLine.Trim()
    if ($name -eq "root") { return "" }
    return $name
}

function Initialize-WslUser {
    $user = Get-WslDefaultUser
    if ($user) { return $user }

    Reset-TuiConsole
    Write-Host "Ubuntu needs its Linux user." -ForegroundColor Yellow
    Write-Host "Create the user and password, then run 'exit' to return to setup." -ForegroundColor White
    & wsl.exe --distribution $script:WslDistro
    if ($LASTEXITCODE -ne 0) { return "" }
    return Get-WslDefaultUser
}

function Get-WslRepoPath {
    $output = @(& wsl.exe --distribution $script:WslDistro --exec wslpath -u $script:RootDir 2>$null)
    if ($LASTEXITCODE -ne 0) { return "" }
    (($output | Select-Object -First 1) -as [string]).Trim()
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $output = @(& wsl.exe --distribution $script:WslDistro --exec wslpath -u $WindowsPath 2>$null)
    if ($LASTEXITCODE -ne 0) { return "" }
    (($output | Select-Object -First 1) -as [string]).Trim()
}

function Test-SetupRepositoryPath {
    param([Parameter(Mandatory)][string]$Path)

    foreach ($requiredPath in @(".git", "configs", "data", "helpers", "lib", "personal", "setup.ps1")) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $requiredPath))) { return $false }
    }
    return $true
}

function Initialize-SetupRepository {
    $targetPath = Join-Path $env:USERPROFILE "win-setup"
    $currentPath = [IO.Path]::GetFullPath($script:RootDir).TrimEnd('\')
    $targetFullPath = [IO.Path]::GetFullPath($targetPath).TrimEnd('\')

    if ($currentPath -ieq $targetFullPath -and (Test-SetupRepositoryPath $targetPath)) {
        return $true
    }

    if (-not (Test-SetupRepositoryPath $targetPath)) {
        if (-not (Install-WslDistro)) {
            return $false
        }

        $linuxUser = Initialize-WslUser
        if ([string]::IsNullOrWhiteSpace($linuxUser)) {
            Write-Log "Ubuntu user initialization is incomplete" "ERROR"
            return $false
        }

        $null = @(& wsl.exe --distribution $script:WslDistro --exec git --version 2>$null)
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Installing Git in Ubuntu..." "INFO"
            $gitOutput = @(& wsl.exe --distribution $script:WslDistro --user root --exec sh -lc `
                "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates" 2>&1)
            $gitExitCode = $LASTEXITCODE
            foreach ($line in $gitOutput) { Write-Log "  $line" "INFO" }
            if ($gitExitCode -ne 0) {
                Write-Log "Git installation failed with exit code $gitExitCode" "ERROR"
                return $false
            }
        }

        $backupPath = $null
        if (Test-Path -LiteralPath $targetPath) {
            if (-not (Ask-YesNo "$targetPath exists but is not the setup repository. Back it up and continue?" $false)) {
                Write-Log "Repository clone cancelled" "WARN"
                return $false
            }
            $backupPath = "$targetPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        }

        $stagingPath = Join-Path $env:USERPROFILE ".win-setup-clone-$([guid]::NewGuid())"
        $wslStagingPath = ConvertTo-WslPath $stagingPath
        if ([string]::IsNullOrWhiteSpace($wslStagingPath)) {
            Write-Log "Could not translate the repository path for WSL" "ERROR"
            return $false
        }

        try {
            Write-Log "Cloning win-setup to $targetPath..." "INFO"
            $cloneOutput = @(& wsl.exe --distribution $script:WslDistro --exec git clone --quiet -- `
                $script:RepositoryUrl $wslStagingPath 2>&1)
            $cloneExitCode = $LASTEXITCODE
            foreach ($line in $cloneOutput) { Write-Log "  $line" "INFO" }
            if ($cloneExitCode -ne 0 -or -not (Test-SetupRepositoryPath $stagingPath)) {
                Write-Log "Repository clone failed with exit code $cloneExitCode" "ERROR"
                return $false
            }

            if ($backupPath) {
                Move-Item -LiteralPath $targetPath -Destination $backupPath
                Write-Log "Backed up existing repository path to $backupPath" "INFO"
            }

            try {
                Move-Item -LiteralPath $stagingPath -Destination $targetPath
            } catch {
                if ($backupPath -and -not (Test-Path -LiteralPath $targetPath)) {
                    Move-Item -LiteralPath $backupPath -Destination $targetPath
                }
                throw
            }
        } catch {
            Write-Log "Repository setup failed: $($_.Exception.Message)" "ERROR"
            return $false
        } finally {
            if (Test-Path -LiteralPath $stagingPath) {
                Remove-Item -LiteralPath $stagingPath -Recurse -Force
            }
        }
    }

    $script:RootDir = $targetPath
    Write-Log "Using setup repository at $targetPath" "INFO"
    return $true
}

function Install-NpipeRelay {
    $installDir = Join-Path $env:LOCALAPPDATA "Programs\npiperelay"
    $executable = Join-Path $installDir "npiperelay.exe"
    if (Test-Path -LiteralPath $executable) {
        $installedHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($installedHash -eq $script:NpipeRelaySha256) {
            Write-Log "npiperelay $script:NpipeRelayVersion is already installed" "INFO"
            return $true
        }
        $backupPath = "$executable.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $executable -Destination $backupPath
        Write-Log "Backed up a different npiperelay build to $backupPath" "INFO"
    }

    $tempDir = Join-Path $env:TEMP "win-setup-npiperelay-$([guid]::NewGuid())"
    $downloadPath = Join-Path $tempDir "npiperelay.exe"
    $url = "https://github.com/albertony/npiperelay/releases/download/v$script:NpipeRelayVersion/npiperelay_windows_amd64.exe"
    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Write-Log "Downloading npiperelay $script:NpipeRelayVersion..." "INFO"
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing
        $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $script:NpipeRelaySha256) { throw "npiperelay checksum mismatch" }

        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $downloadPath -Destination $executable -Force
        Write-Log "Installed npiperelay" "SUCCESS"
        return $true
    } catch {
        Write-Log "npiperelay installation failed: $($_.Exception.Message)" "ERROR"
        return $false
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }
}

function Invoke-WslBootstrap {
    New-ConfigLink "$script:RootDir/configs/wsl/.wslconfig" "$env:USERPROFILE\.wslconfig"
    Write-Log "Updating WSL..." "INFO"
    $updateOutput = @(& wsl.exe --update 2>&1)
    $updateExitCode = $LASTEXITCODE
    foreach ($line in $updateOutput) { Write-Log "  $line" "INFO" }
    if ($updateExitCode -ne 0) {
        Write-Log "Store update failed with exit code $updateExitCode; retrying direct download" "WARN"
        $updateOutput = @(& wsl.exe --update --web-download 2>&1)
        $updateExitCode = $LASTEXITCODE
        foreach ($line in $updateOutput) { Write-Log "  $line" "INFO" }
        if ($updateExitCode -ne 0) {
            Write-Log "WSL update failed with exit code $updateExitCode" "ERROR"
            return $false
        }
    }

    $wasInstalled = Test-WslDistroInstalled
    if (-not (Install-WslDistro)) { return $false }

    $linuxUser = if ($wasInstalled) { Initialize-WslUser } else {
        Reset-TuiConsole
        Write-Host "Ubuntu needs its Linux user." -ForegroundColor Yellow
        Write-Host "Create the user and password, then run 'exit' to return to setup." -ForegroundColor White
        & wsl.exe --distribution $script:WslDistro
        if ($LASTEXITCODE -eq 0) { Get-WslDefaultUser } else { "" }
    }
    if ([string]::IsNullOrWhiteSpace($linuxUser)) {
        Write-Log "Ubuntu user initialization is incomplete" "ERROR"
        return $false
    }

    $repoPath = Get-WslRepoPath
    if ([string]::IsNullOrWhiteSpace($repoPath)) {
        Write-Log "Could not translate the repository path for WSL" "ERROR"
        return $false
    }

    $relayPath = ConvertTo-WslPath (Join-Path $env:LOCALAPPDATA "Programs\npiperelay\npiperelay.exe")
    if ([string]::IsNullOrWhiteSpace($relayPath)) {
        Write-Log "Could not translate the npiperelay path for WSL" "ERROR"
        return $false
    }

    Write-Log "Provisioning $script:WslDistro for $linuxUser..." "INFO"
    $bootstrapPath = "$repoPath/configs/wsl/bootstrap.sh"
    $output = @(& wsl.exe --distribution $script:WslDistro --user root --exec bash $bootstrapPath $linuxUser $repoPath $relayPath 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Log "  $line" "INFO" }
    if ($exitCode -ne 0) {
        Write-Log "Ubuntu bootstrap failed with exit code $exitCode" "ERROR"
        return $false
    }

    $existingName = @(& wsl.exe --distribution $script:WslDistro --exec git config --global user.name 2>$null) | Select-Object -First 1
    $existingEmail = @(& wsl.exe --distribution $script:WslDistro --exec git config --global user.email 2>$null) | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($existingName) -or [string]::IsNullOrWhiteSpace($existingEmail)) {
        Reset-TuiConsole
        $name = Ask-Input "Git user name" $existingName
        $email = Ask-Input "Git user email" $existingEmail
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            & wsl.exe --distribution $script:WslDistro --exec git config --global user.name $name
        }
        if (-not [string]::IsNullOrWhiteSpace($email)) {
            & wsl.exe --distribution $script:WslDistro --exec git config --global user.email $email
        }
    }

    & wsl.exe --shutdown

    Write-Log "Ubuntu daily environment configured" "SUCCESS"
    return $true
}

function Disable-WindowsOpenSshAgent {
    $service = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
    if ($null -eq $service) { return $true }
    try {
        if ($service.Status -ne "Stopped") { Stop-Service -Name "ssh-agent" -Force }
        Set-Service -Name "ssh-agent" -StartupType Disabled
        Write-Log "Disabled Windows OpenSSH Authentication Agent for Bitwarden" "SUCCESS"
        return $true
    } catch {
        Write-Log "Failed to disable Windows OpenSSH Authentication Agent: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Install-VsCodeWslExtension {
    Refresh-EnvironmentPath
    if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Log "VS Code CLI unavailable; WSL extension was not installed" "WARN"
        return $false
    }
    $output = @(& code --install-extension ms-vscode-remote.remote-wsl --force 2>&1)
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Log "  $line" "INFO" }
    return $exitCode -eq 0
}
