# win-setup

Guided PowerShell setup script for a fresh Windows 11 24H2+ install.

## What it does

- Enables WSL2 + Virtual Machine Platform
- Enables symlinks, long paths, developer mode
- Installs apps via `winget import` from `apps.json`
- Installs Arch Linux on WSL
- Applies Explorer power-user tweaks
- Applies mild privacy hardening
- Activates Ultimate Performance power plan
- Deploys komorebi config with workspace rules, status bar, and auto-start
- Adds app-launch hotkeys
- Deploys Neovim config to `%LOCALAPPDATA%\nvim`
- Deploys nushell config with vi mode, fuzzy completions, aliases
- Deploys color scheme for Windows Terminal
- Interactive git setup 

## Usage

> [!NOTE]  
> The script will prompt for elevation if not running as admin.

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```

## Known Issues
- PowerToys must load after komorebi or PowerToys keybinds will take precedence.
