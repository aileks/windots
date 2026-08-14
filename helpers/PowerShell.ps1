function Invoke-PowerShellProfileSetup {
    Refresh-EnvironmentPath
    if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        Write-Log "PowerShell 7 is unavailable" "ERROR"
        return $false
    }

    $moduleScript = @'
$ErrorActionPreference = "Stop"
$repository = Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue
$originalPolicy = if ($repository) { $repository.InstallationPolicy } else { "Untrusted" }
try {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
    if (-not (Get-Module -ListAvailable PSFzf)) {
        Install-Module PSFzf -Scope CurrentUser -Force -AllowClobber
    }
} finally {
    Set-PSRepository -Name PSGallery -InstallationPolicy $originalPolicy -ErrorAction SilentlyContinue
}
'@
    # Windows PowerShell's native argument marshalling strips quotes from a
    # multiline -Command argument. EncodedCommand keeps the script byte-exact.
    $encodedScript = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($moduleScript))
    $nativeResult = Invoke-NativeCommand -FilePath "pwsh" -ArgumentList @(
        "-NoProfile", "-EncodedCommand", $encodedScript
    )
    if ($nativeResult.ExitCode -ne 0) {
        Write-Log "PSFzf failed: exit $($nativeResult.ExitCode)" "ERROR"
        return $false
    }

    $profilePath = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "PowerShell\Microsoft.PowerShell_profile.ps1"
    New-ConfigLink "$script:RootDir/configs/windows/powershell/Microsoft.PowerShell_profile.ps1" $profilePath
    New-ConfigLink "$script:RootDir/configs/windows/starship/starship.toml" "$env:USERPROFILE\.config\starship.toml"
    Write-Log "PowerShell profile linked" "SUCCESS"
    return $true
}
