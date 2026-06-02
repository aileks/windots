# win-setup

Guided PowerShell setup script for a fresh Windows 11 24H2+ install.

## What it does

- Enables WSL2 + Virtual Machine Platform
- Enables symlinks, long paths, developer mode
- Installs apps via winget
- Installs Arch Linux on WSL with mirrored networking
- Applies Explorer power-user tweaks
- Applies mild privacy hardening
- Activates Ultimate Performance power plan
- Deploys komorebi config with workspace rules and auto-start
- Deploys nushell config with vi mode, fuzzy completions, aliases
- Deploys color scheme for Windows Terminal
- Interactive git setup 

## Usage

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```

> [!NOTE]  
> The script will prompt for elevation if not running as admin. If WSL features require a reboot, the script registers a RunOnce entry and resumes automatically after restart.

> [!NOTE]  
> Arch is installed with `--no-launch`, so no Linux user is created during setup. After the script finishes, run `wsl -d archlinux` once to create your user account.

## Config locations

| Config | Destination |
|---|---|
| komorebi.json | `~\komorebi.json` |
| whkdrc | `~\.config\whkdrc` |
| nushell env.nu | `%APPDATA%\nushell\env.nu` |
| nushell config.nu | `%APPDATA%\nushell\config.nu` |
| .wslconfig | `~\.wslconfig` |
| wsl.conf | `/etc/wsl.conf` (inside WSL) |
| Windows Terminal | merged into `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` |

