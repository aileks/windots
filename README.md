# Windows Setup

Opinionated setup for Windows 11 24H2+. Use at your own risk.

## Usage

```powershell
irm https://aileks.dev/win | iex
```

Or manually:

```powershell
git clone https://codeberg.org/aileks/win-setup.git %USERPROFILE%/.dotfiles
cd %USERPROFILE%/.dotfiles

Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```
