function New-ConfigLink {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Dest
    )

    $parent = Split-Path $Dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

    $sourceFull = (Resolve-Path $Source).Path

    $item = Get-Item -LiteralPath $Dest -Force -ErrorAction SilentlyContinue
    if ($null -ne $item) {
        if ($item.LinkType -eq 'SymbolicLink' -and $item.Target -eq $sourceFull) {
            Write-Log "Link exists: $Dest" "INFO"
            return
        }
        if ($item.LinkType -ne 'SymbolicLink') {
            $backup = "$Dest.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item -LiteralPath $Dest -Destination $backup -Force
            Write-Log "Backup created: $Dest" "INFO"
        }
        else {
            Remove-Item -LiteralPath $Dest -Force
        }
    }

    New-Item -ItemType SymbolicLink -Path $Dest -Target $sourceFull -Force | Out-Null
    Write-Log "Linked: $Dest" "INFO"
}
