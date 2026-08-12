$script:WslDistro = "archlinux"
$script:NpipeRelayVersion = "1.11.4"
$script:NpipeRelaySha256 = "cea82cf5c9c22a28bef8075750acb7958f766393baebff4597cf21442f71c4b3"

function Test-WslPlatformEnabled {
    try {
        $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--list", "--quiet")
        return $result.ExitCode -eq 0
    } catch {
        Write-Log "WSL failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Enable-WslPlatformAndReboot {
    Register-ResumeAfterReboot -ScriptPath $script:SetupScript
    Write-Log "Installing WSL" "INFO"
    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--install", "--no-distribution")
    if ($result.ExitCode -ne 0) {
        Clear-ResumeAfterReboot
        Write-Log "WSL enablement failed: exit $($result.ExitCode)" "ERROR"
        return $false
    }

    Set-StateValue "rebootRequired" $true
    Write-Log "WSL enabled" "SUCCESS"
    Restart-Computer
    return $true
}

function Get-WslDistroNames {
    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--list", "--quiet")
    if ($result.ExitCode -ne 0) { return @() }
    @($result.Output | ForEach-Object { ([string]$_).Replace([string][char]0, "").Trim() } | Where-Object { $_ })
}

function Test-WslDistroInstalled {
    @(Get-WslDistroNames) -contains $script:WslDistro
}

function Install-WslDistro {
    if (Test-WslDistroInstalled) {
        Set-StateValue "selectedWslDistro" $script:WslDistro
        Write-Log "Arch Linux exists" "INFO"
        return $true
    }

    Write-Log "Installing Arch Linux" "INFO"
    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
        "--install", "--distribution", $script:WslDistro, "--no-launch"
    )
    if ($result.ExitCode -ne 0) {
        Write-Log "Arch Linux install failed: exit $($result.ExitCode)" "ERROR"
        return $false
    }
    if (-not (Test-WslDistroInstalled)) {
        Write-Log "Arch Linux unavailable after installation" "ERROR"
        return $false
    }
    Set-StateValue "selectedWslDistro" $script:WslDistro
    return $true
}

function Get-WslDefaultUser {
    if (-not (Test-WslDistroInstalled)) { return "" }

    $storedUser = [string](Get-StateValue "selectedWslUser")
    if (-not [string]::IsNullOrWhiteSpace($storedUser)) {
        $storedResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
            "--distribution", $script:WslDistro, "--user", "root", "--exec", "id", "--user", $storedUser
        ) -NoConsole
        if ($storedResult.ExitCode -eq 0) { return $storedUser }
    }

    # The official Arch image starts as root. UID 1000 is the user created by
    # this installer and lets an interrupted setup resume without prompting.
    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
        "--distribution", $script:WslDistro, "--user", "root", "--exec",
        "sh", "-lc", "getent passwd 1000 | cut -d: -f1"
    ) -NoConsole
    if ($result.ExitCode -ne 0) { return "" }
    $outputLines = @($result.Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ })
    $lastLine = $outputLines | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($lastLine)) { return "" }
    $name = ([string]$lastLine).Trim()
    if ($name -eq "root") { return "" }
    return $name
}

function Test-WslUserPasswordSet {
    param([Parameter(Mandatory)][string]$User)

    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
        "--distribution", $script:WslDistro, "--user", "root", "--exec",
        "env", "LC_ALL=C", "passwd", "--status", $User
    ) -NoConsole
    if ($result.ExitCode -ne 0) { return $false }
    $status = (@($result.Output) -join " ").Trim()
    return $status -match "^$([regex]::Escape($User))\s+P\s"
}

function Set-WslUserPassword {
    param([Parameter(Mandatory)][string]$User)

    Write-Host "Set Arch Linux password for $User" -ForegroundColor Yellow
    & wsl.exe --distribution $script:WslDistro --user root --exec passwd $User
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Log "Arch Linux password setup failed: exit $exitCode" "ERROR"
        return $false
    }
    return Test-WslUserPasswordSet -User $User
}

function Initialize-WslUser {
    $user = Get-WslDefaultUser
    if (-not $user) {
        $defaultUser = $env:USERNAME.ToLowerInvariant() -replace '[^a-z0-9_-]', ''
        if ($defaultUser -notmatch '^[a-z_]') { $defaultUser = "user$defaultUser" }
        if ($defaultUser.Length -gt 32) { $defaultUser = $defaultUser.Substring(0, 32) }

        while ($true) {
            $user = Ask-Input "Arch Linux username" $defaultUser
            if ($user -match '^[a-z_][a-z0-9_-]{0,31}$' -and $user -ne "root") { break }
            Write-Host "Use 1-32 lowercase letters, numbers, underscores, or hyphens; do not use root." `
                -ForegroundColor Yellow
        }

        $createResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
            "--distribution", $script:WslDistro, "--user", "root", "--exec",
            "useradd", "--create-home", "--groups", "wheel", "--shell", "/bin/bash", $user
        )
        if ($createResult.ExitCode -ne 0) {
            Write-Log "Arch Linux user creation failed: exit $($createResult.ExitCode)" "ERROR"
            return ""
        }
    }

    if (-not (Test-WslUserPasswordSet -User $user) -and -not (Set-WslUserPassword -User $user)) {
        return ""
    }
    Set-StateValue "selectedWslUser" $user
    return $user
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
        "--distribution", $script:WslDistro, "--user", "root", "--exec", "wslpath", "-u", $WindowsPath
    )
    if ($result.ExitCode -ne 0) { return "" }
    (($result.Output | Select-Object -First 1) -as [string]).Trim()
}

function Convert-WslConfigPayloadToLf {
    param([Parameter(Mandatory)][string]$Root)

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse) {
        $content = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $normalized = $content.Replace("`r`n", "`n").Replace("`r", "`n")
        if ($normalized -ne $content) {
            [IO.File]::WriteAllText($file.FullName, $normalized, $utf8)
        }
    }
}

function Copy-WslConfigPayload {
    param([Parameter(Mandatory)][string]$LinuxUser)

    $uncHome = "\\wsl.localhost\$script:WslDistro\home\$LinuxUser"
    if (-not (Test-Path -LiteralPath $uncHome)) {
        Write-Log "Arch Linux home unavailable: $uncHome" "ERROR"
        return $null
    }

    $managedRoot = Join-Path $uncHome ".local\share\windows-setup-script-configs"
    $stagingRoot = "$managedRoot.stage-$([guid]::NewGuid())"
    $payloadFiles = @(
        @{ Source = "configs\wsl\bootstrap.sh"; Relative = "wsl\bootstrap.sh" }
        @{ Source = "configs\wsl\zsh"; Relative = "zsh" }
        @{ Source = "configs\wsl\wsl.conf"; Relative = "wsl\wsl.conf" }
        @{ Source = "configs\wsl\bitwarden-ssh-agent.zsh"; Relative = "wsl\bitwarden-ssh-agent.zsh" }
        @{ Source = "configs\wsl\nvim"; Relative = "nvim" }
        @{ Source = "configs\wsl\tmux"; Relative = "tmux" }
        @{ Source = "configs\wsl\btop"; Relative = "btop" }
        @{ Source = "configs\wsl\fastfetch"; Relative = "fastfetch" }
        @{ Source = "configs\common\starship\starship.toml"; Relative = "starship\starship.toml" }
        @{ Source = "configs\common\bat"; Relative = "bat" }
    )

    try {
        foreach ($entry in $payloadFiles) {
            $source = Join-Path $script:RootDir $entry.Source
            if (-not (Test-Path -LiteralPath $source)) {
                throw "WSL config source is missing: $source"
            }
            $destination = Join-Path $stagingRoot $entry.Relative
            $parent = Split-Path $destination -Parent
            if (-not (Test-Path -LiteralPath $parent)) {
                New-Item -Path $parent -ItemType Directory -Force | Out-Null
            }
            if ((Get-Item -LiteralPath $source).PSIsContainer) {
                Copy-Item -LiteralPath $source -Destination $destination -Recurse -Force
            } else {
                Copy-Item -LiteralPath $source -Destination $destination -Force
            }
        }
        Convert-WslConfigPayloadToLf -Root $stagingRoot

        if (Test-Path -LiteralPath $managedRoot) {
            Remove-Item -LiteralPath $managedRoot -Recurse -Force
        }
        Move-Item -LiteralPath $stagingRoot -Destination $managedRoot
        $linuxRoot = "/home/$LinuxUser/.local/share/windows-setup-script-configs"
        Write-Log "WSL configs copied" "SUCCESS"
        return [PSCustomObject]@{ UncPath = $managedRoot; LinuxPath = $linuxRoot }
    } catch {
        Write-Log "WSL config copy failed: $($_.Exception.Message)" "ERROR"
        return $null
    } finally {
        if (Test-Path -LiteralPath $stagingRoot) {
            Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Install-NpipeRelay {
    $installDir = Join-Path $env:LOCALAPPDATA "Programs\npiperelay"
    $executable = Join-Path $installDir "npiperelay.exe"
    if (Test-Path -LiteralPath $executable) {
        $installedHash = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($installedHash -eq $script:NpipeRelaySha256) {
            Write-Log "npiperelay exists" "INFO"
            return $true
        }
        $backupPath = "$executable.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $executable -Destination $backupPath
        Write-Log "npiperelay backed up" "INFO"
    }

    $tempDir = Join-Path $env:TEMP "windows-setup-script-npiperelay-$([guid]::NewGuid())"
    $downloadPath = Join-Path $tempDir "npiperelay.exe"
    $url = "https://github.com/albertony/npiperelay/releases/download/v$script:NpipeRelayVersion/npiperelay_windows_amd64.exe"
    try {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        Write-Log "Downloading npiperelay" "INFO"
        Invoke-WebRequest -Uri $url -OutFile $downloadPath -UseBasicParsing
        $actualHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actualHash -ne $script:NpipeRelaySha256) { throw "npiperelay checksum mismatch" }

        New-Item -Path $installDir -ItemType Directory -Force | Out-Null
        Copy-Item -LiteralPath $downloadPath -Destination $executable -Force
        Write-Log "npiperelay installed" "SUCCESS"
        return $true
    } catch {
        Write-Log "npiperelay failed: $($_.Exception.Message)" "ERROR"
        return $false
    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }
}

function Invoke-WslBootstrap {
    param([AllowNull()][string]$RelayPath = $null)

    New-ConfigLink "$script:RootDir/configs/wsl/.wslconfig" "$env:USERPROFILE\.wslconfig"
    if (-not (Install-WslDistro)) { return $false }

    # Applying .wslconfig requires all WSL instances to stop before Arch Linux is
    # relaunched. A non-zero shutdown here is reported but does not prevent the
    # first-run experience from repairing an otherwise healthy installation.
    $initialShutdown = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--shutdown")
    if ($initialShutdown.ExitCode -ne 0) {
        Write-Log "WSL shutdown failed: exit $($initialShutdown.ExitCode)" "WARN"
    }

    try {
        $linuxUser = Initialize-WslUser
        if ([string]::IsNullOrWhiteSpace($linuxUser)) {
            return $false
        }

        $configPayload = Copy-WslConfigPayload -LinuxUser $linuxUser
        if ($null -eq $configPayload) {
            return $false
        }
        $configRoot = $configPayload.LinuxPath

        if ($null -eq $RelayPath) {
            $windowsRelayPath = Join-Path $env:LOCALAPPDATA "Programs\npiperelay\npiperelay.exe"
            $RelayPath = if (Test-Path -LiteralPath $windowsRelayPath) { $windowsRelayPath } else { "" }
        }
        $wslRelayPath = ""
        if (-not [string]::IsNullOrWhiteSpace($RelayPath)) {
            $wslRelayPath = ConvertTo-WslPath $RelayPath
            if ([string]::IsNullOrWhiteSpace($wslRelayPath)) {
                Write-Log "npiperelay path failed" "ERROR"
                return $false
            }
        } else {
            Write-Log "Bitwarden relay unavailable" "WARN"
        }

        Write-Log "Configuring Arch Linux" "INFO"
        $bootstrapPath = "$configRoot/wsl/bootstrap.sh"
        $bootstrapArguments = @(
            "--distribution", $script:WslDistro, "--user", "root", "--exec",
            "bash", $bootstrapPath, $linuxUser, $configRoot, $wslRelayPath
        )
        $bootstrapResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList $bootstrapArguments
        if ($bootstrapResult.ExitCode -ne 0) {
            Write-Log "Arch Linux setup failed: exit $($bootstrapResult.ExitCode)" "ERROR"
            return $false
        }

        $defaultResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
            "--set-default", $script:WslDistro
        )
        if ($defaultResult.ExitCode -ne 0) {
            Write-Log "Arch Linux default distro setup failed: exit $($defaultResult.ExitCode)" "ERROR"
            return $false
        }

        Write-Log "Arch Linux configured" "SUCCESS"
        return $true
    } finally {
        $shutdownResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--shutdown")
        if ($shutdownResult.ExitCode -ne 0) {
            Write-Log "WSL shutdown failed: exit $($shutdownResult.ExitCode)" "WARN"
        }
    }
}

function Disable-WindowsOpenSshAgent {
    $service = Get-Service -Name "ssh-agent" -ErrorAction SilentlyContinue
    if ($null -eq $service) { return $true }
    try {
        if ($service.Status -ne "Stopped") { Stop-Service -Name "ssh-agent" -Force }
        Set-Service -Name "ssh-agent" -StartupType Disabled
        Write-Log "OpenSSH agent disabled" "SUCCESS"
        return $true
    } catch {
        Write-Log "OpenSSH agent failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}
