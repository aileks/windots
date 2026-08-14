# Windows 11 Setup

Opinionated setup for Windows 11 24H2 or later. Use at your own risk.

## Install

Run from an elevated Windows PowerShell session:

```powershell
irm https://aileks.dev/win | iex
```

Or clone and run it manually:

```powershell
git clone https://github.com/aileks/windots.git "$env:USERPROFILE\.dotfiles"
Set-Location "$env:USERPROFILE\.dotfiles"
Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```
