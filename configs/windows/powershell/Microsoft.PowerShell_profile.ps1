$env:EDITOR = "code --wait"
$env:VISUAL = $env:EDITOR

Set-Alias ff fastfetch

if (Get-Command coreutils-manager -ErrorAction SilentlyContinue) {
    @("cat", "cp", "echo", "ls", "mv", "pwd", "rm", "rmdir", "sleep", "sort", "tee") |
        ForEach-Object { Remove-Item "Alias:$_" -Force -ErrorAction SilentlyContinue }
    Remove-Item Function:mkdir -Force -ErrorAction SilentlyContinue
}

Set-PSReadLineOption -EditMode Vi
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadLineOption -Colors @{
    Default                = "#BBB3A9"
    Comment                = "#58534C"
    Keyword                = "#9A788F"
    String                 = "#E17A3F"
    Operator               = "#879B5C"
    Variable               = "#BBB3A9"
    Command                = "#6785A1"
    Parameter              = "#879B5C"
    Type                   = "#58918C"
    Number                 = "#58918C"
    Member                 = "#DDD5CA"
    Error                  = "#B34A45"
    Emphasis               = "#D9A441"
    Selection              = "#23201C"
    InlinePrediction       = "#58534C"
    ListPredictionSelected = "#23201C"
}

$env:FZF_DEFAULT_OPTS = @(
    "--color=fg:#BBB3A9,fg+:#DDD5CA,bg:#131210,bg+:#34312D"
    "--color=hl:#E17A3F,hl+:#D9A441,info:#9A938A,marker:#E17A3F"
    "--color=prompt:#E17A3F,spinner:#DC8853,pointer:#D9A441,header:#B34A45"
    "--color=border:#E17A3F,query:#DDD5CA,gutter:#131210"
    "--highlight-line --info=inline-right --layout=reverse --pointer=█ --scrollbar=▌ --multi --border=top"
) -join " "

if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) {
    Set-PSReadLineOption -PredictionSource History
}

if (Get-Module -ListAvailable PSFzf) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider "Ctrl+t" -PSReadlineChordReverseHistory "Ctrl+r"
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}
