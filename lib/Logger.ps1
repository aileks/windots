$script:LogPath = ""

function Initialize-Log {
    param([string]$Path)
    $script:LogPath = $Path
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}

function Write-Log {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet("INFO","WARN","ERROR","SUCCESS")]
        [string]$Level = "INFO",
        [switch]$NoConsole
    )

    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"

    if ($script:LogPath) {
        Add-Content -Path $script:LogPath -Value $line -Encoding UTF8
    }

    $color = switch ($Level) {
        "INFO"    { "Cyan" }
        "WARN"    { "Yellow" }
        "ERROR"   { "Red" }
        "SUCCESS" { "Green" }
    }
    if (-not $NoConsole) {
        Write-Host $Message -ForegroundColor $color
    }
}

function Remove-NativeOutputFormatting {
    param([AllowEmptyString()][string]$Text)

    if ($null -eq $Text) { return "" }

    # Strip ANSI CSI/OSC sequences and normalize progress-style carriage returns.
    $clean = $Text.Replace([string][char]0, "")
    $escapePattern = [regex]::Escape([string][char]27)
    $clean = $clean -replace ($escapePattern + "\][^\x07]*(?:\x07|" + $escapePattern + "\\)"), ""
    $clean = $clean -replace ($escapePattern + "\[[0-?]*[ -/]*[@-~]"), ""
    $clean = $clean -replace "`r", ""
    return $clean
}

function Invoke-NativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")]
        [string]$LogLevel = "INFO",
        [string]$OutputPrefix = "",
        [switch]$NoConsole
    )

    $output = New-Object System.Collections.Generic.List[string]
    $exitCode = 1
    $previousErrorActionPreference = $ErrorActionPreference
    $nativePreferenceVariable = Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    $hadNativePreference = $null -ne $nativePreferenceVariable
    $previousNativePreference = if ($hadNativePreference) { $nativePreferenceVariable.Value } else { $null }

    try {
        # Windows PowerShell surfaces native stderr as ErrorRecord objects. Keep it
        # visible without allowing the caller's Stop preference to abort the command.
        $ErrorActionPreference = "Continue"
        if ($hadNativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $false -Scope Local
        }

        & $FilePath @ArgumentList 2>&1 | ForEach-Object {
            $text = if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $_.Exception.Message
            } else {
                [string]$_
            }

            foreach ($line in @($text -split "`n")) {
                $clean = Remove-NativeOutputFormatting -Text $line
                $output.Add($clean)
                if (-not $NoConsole) {
                    Write-Host "$OutputPrefix$clean"
                }
                Write-Log -Message "$OutputPrefix$clean" -Level $LogLevel -NoConsole
            }
        }
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 0 }
    } catch {
        $clean = Remove-NativeOutputFormatting -Text $_.Exception.Message
        $output.Add($clean)
        if (-not $NoConsole) {
            Write-Host "$OutputPrefix$clean" -ForegroundColor Red
        }
        Write-Log -Message "$OutputPrefix$clean" -Level "ERROR" -NoConsole
        $exitCode = 1
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
        if ($hadNativePreference) {
            Set-Variable -Name PSNativeCommandUseErrorActionPreference -Value $previousNativePreference -Scope Local
        }
    }

    [PSCustomObject]@{
        FilePath  = $FilePath
        Arguments = @($ArgumentList)
        ExitCode  = [int]$exitCode
        Output    = @($output)
        Succeeded = ([int]$exitCode -eq 0)
    }
}
