function Ask-YesNo {
    param(
        [Parameter(Mandatory)][string]$Question,
        [bool]$Default = $true
    )

    $hint = if ($Default) { "[Y/n]" } else { "[y/N]" }
    $prompt = "$Question $hint"

    Write-Host $prompt -NoNewline -ForegroundColor White
    Write-Host " " -NoNewline
    $reply = Read-Host

    if ([string]::IsNullOrWhiteSpace($reply)) { return $Default }
    return $reply.Trim() -match "^[Yy]"
}

function Ask-Input {
    param(
        [Parameter(Mandatory)][string]$Question,
        [string]$Default = ""
    )

    if ($Default) {
        Write-Host "$Question " -NoNewline -ForegroundColor White
        Write-Host "($Default)" -NoNewline -ForegroundColor DarkGray
        Write-Host ": " -NoNewline
    } else {
        Write-Host "${Question}: " -NoNewline -ForegroundColor White
    }
    $reply = Read-Host

    if ([string]::IsNullOrWhiteSpace($reply)) { return $Default }
    return $reply.Trim()
}

function Read-CatalogCategorySelection {
    param(
        [Parameter(Mandatory)]$Category
    )

    $items = @($Category.items)
    while ($true) {
        Write-Host ""
        Write-Host $Category.name -ForegroundColor White

        for ($i = 0; $i -lt $items.Count; $i++) {
            $item = $items[$i]
            $label = "  {0}. {1}" -f ($i + 1), $item.name
            if ($item.description) {
                $label = "$label - $($item.description)"
            }
            Write-Host $label -ForegroundColor Cyan
        }

        $prompt = if ($Category.allowMultiple) {
            "Select $($Category.name) (comma-separated numbers, a for all, blank to skip)"
        } else {
            "Select $($Category.name) (one number, blank to skip)"
        }

        $reply = Ask-Input $prompt ""
        if ([string]::IsNullOrWhiteSpace($reply)) { return @() }

        $normalized = $reply.Trim().ToLowerInvariant()
        if ($normalized -eq "a") {
            if ($Category.allowMultiple) { return $items }
            Write-Log "  Pick a single option, or leave blank to skip." "WARN"
            continue
        }

        $tokens = @($reply -split "[,\s]+" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $invalid = @()
        $indexes = @()

        foreach ($token in $tokens) {
            if ($token -notmatch "^\d+$") {
                $invalid += $token
                continue
            }

            $index = [int]$token
            if ($index -lt 1 -or $index -gt $items.Count) {
                $invalid += $token
            } else {
                $indexes += $index
            }
        }

        $indexes = @($indexes | Select-Object -Unique)
        if ($invalid.Count -gt 0) {
            Write-Log "  Invalid selection: $($invalid -join ', ')" "WARN"
            continue
        }

        if (-not $Category.allowMultiple -and $indexes.Count -gt 1) {
            Write-Log "  Pick only one option, or leave blank to skip." "WARN"
            continue
        }

        return @($indexes | ForEach-Object {
            $selectedIndex = [int]$_ - 1
            $items[$selectedIndex]
        })
    }
}
