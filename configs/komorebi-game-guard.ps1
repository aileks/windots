# komorebi-game-guard.ps1
# Suspends whkd while a fullscreen game (e.g. FFXIV) is focused so that `alt`
# reaches the game natively instead of being captured as the komorebi modifier,
# then restarts whkd when you tab away. komorebi itself keeps running throughout.
# Also acts as a whkd babysitter: relaunches whkd if it ever dies while you're
# not in a game.

$ErrorActionPreference = 'SilentlyContinue'

# Process names (as shown by `Get-Process`, without the .exe) that should own `alt`.
$games = @('ffxiv_dx11')

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class Fg {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
"@

function Get-ForegroundProcessName {
    $hwnd = [Fg]::GetForegroundWindow()
    if ($hwnd -eq [IntPtr]::Zero) { return $null }
    $procId = [uint32]0
    [void][Fg]::GetWindowThreadProcessId($hwnd, [ref]$procId)
    if ($procId -eq 0) { return $null }
    return (Get-Process -Id $procId -ErrorAction SilentlyContinue).ProcessName
}

while ($true) {
    $fg = Get-ForegroundProcessName
    $inGame = $fg -and ($games -contains $fg)
    $whkd = Get-Process -Name whkd -ErrorAction SilentlyContinue

    if ($inGame -and $whkd) {
        # Game took focus -> get out of the way so alt is native in-game.
        Stop-Process -Name whkd -Force
    }
    elseif (-not $inGame -and -not $whkd) {
        # Back on the desktop (or whkd died) -> restore komorebi hotkeys.
        Start-Process whkd -WindowStyle Hidden
    }

    Start-Sleep -Milliseconds 1000
}
