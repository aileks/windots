$script:WslDistro = "Ubuntu"
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
    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--install")
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

function Resolve-WslDistro {
    $names = @(Get-WslDistroNames)
    if ("Ubuntu" -notin $names) { return $false }

    $script:WslDistro = "Ubuntu"
    Set-StateValue "selectedWslDistro" $script:WslDistro
    Write-Log "Ubuntu found: $script:WslDistro" "INFO"
    return $true
}

function Install-WslDistro {
    if (Resolve-WslDistro) { return $true }

    Write-Log "Installing Ubuntu" "INFO"
    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--install")
    if ($result.ExitCode -ne 0) {
        Write-Log "Ubuntu install failed: exit $($result.ExitCode)" "ERROR"
        return $false
    }
    if (-not (Resolve-WslDistro)) {
        Write-Log "Ubuntu unavailable after installation" "ERROR"
        return $false
    }
    return $true
}

function Get-WslDefaultUser {
    if (-not (Test-WslDistroInstalled)) { return "" }

    # Read the registered UID before invoking the distro. Calling `wsl --exec`
    # against an uninitialized distro can consume its first launch as root and
    # bypass the interactive Ubuntu user-creation flow we need to show.
    try {
        $registrations = @(Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss" -ErrorAction Stop)
        $registration = $registrations | ForEach-Object { Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop } | `
            Where-Object { $_.DistributionName -eq $script:WslDistro } | `
            Select-Object -First 1
    } catch {
        Write-Log "Ubuntu registration failed: $($_.Exception.Message)" "WARN"
        return ""
    }
    if ($null -eq $registration -or $null -eq $registration.DefaultUid) { return "" }
    $defaultUid = [uint32]$registration.DefaultUid
    if ($defaultUid -eq 0) { return "" }

    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
        "--distribution", $script:WslDistro, "--user", "root", "--exec", "id", "-un", $defaultUid
    )
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

    Write-Host "Set Ubuntu password for $User" -ForegroundColor Yellow
    & wsl.exe --distribution $script:WslDistro --user root --exec passwd $User
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Log "Ubuntu password setup failed: exit $exitCode" "ERROR"
        return $false
    }
    return Test-WslUserPasswordSet -User $User
}

function Initialize-WslUser {
    $user = Get-WslDefaultUser
    if ($user) {
        if (-not (Test-WslUserPasswordSet -User $user) -and -not (Set-WslUserPassword -User $user)) {
            return ""
        }
        return $user
    }

    Write-Host "Create Ubuntu user, then exit" -ForegroundColor Yellow
    & wsl.exe --distribution $script:WslDistro
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Log "Ubuntu first run failed: exit $exitCode" "ERROR"
        return ""
    }

    $user = Get-WslDefaultUser
    if ([string]::IsNullOrWhiteSpace($user)) {
        Write-Log "Ubuntu user incomplete" "ERROR"
        return ""
    }
    if (-not (Test-WslUserPasswordSet -User $user) -and -not (Set-WslUserPassword -User $user)) {
        return ""
    }
    return $user
}

function ConvertTo-WslPath {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $result = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @(
        "--distribution", $script:WslDistro, "--exec", "wslpath", "-u", $WindowsPath
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
        Write-Log "Ubuntu home unavailable: $uncHome" "ERROR"
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

    # Applying .wslconfig requires all WSL instances to stop before Ubuntu is
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

        Write-Log "Configuring Ubuntu" "INFO"
        $bootstrapPath = "$configRoot/wsl/bootstrap.sh"
        $bootstrapArguments = @(
            "--distribution", $script:WslDistro, "--user", "root", "--exec",
            "bash", $bootstrapPath, $linuxUser, $configRoot, $wslRelayPath
        )
        $bootstrapResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList $bootstrapArguments
        if ($bootstrapResult.ExitCode -ne 0) {
            $bootstrapText = @($bootstrapResult.Output) -join "`n"
            if ($bootstrapText -match '(?im)Release file(?: for)? .* is not valid yet') {
                Write-Log "Ubuntu clock skew detected" "WARN"
                $terminateResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList @("--terminate", $script:WslDistro)
                if ($terminateResult.ExitCode -ne 0) {
                    Write-Log "Ubuntu restart failed: exit $($terminateResult.ExitCode)" "WARN"
                }
                $bootstrapResult = Invoke-NativeCommand -FilePath "wsl.exe" -ArgumentList $bootstrapArguments
            }
        }
        if ($bootstrapResult.ExitCode -ne 0) {
            Write-Log "Ubuntu setup failed: exit $($bootstrapResult.ExitCode)" "ERROR"
            return $false
        }

        Write-Log "Ubuntu configured" "SUCCESS"
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
