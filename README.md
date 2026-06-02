# win-setup

Guided PowerShell setup script for a fresh Windows 11 24H2+ install.

## What it does

- Enables WSL2 + Virtual Machine Platform
- Enables symlinks, long paths, developer mode
- Installs apps via `winget import` from `apps.json`
- Installs Arch Linux on WSL (web-download, no Microsoft Store needed)
- Applies Explorer power-user tweaks
- Applies mild privacy hardening
- Activates Ultimate Performance power plan
- Deploys komorebi config with workspace rules and auto-start (whkd, Alt modifier)
- Deploys nushell config with vi mode, fuzzy completions, aliases
- Deploys color scheme for Windows Terminal
- Interactive git setup 

## Usage

> [!NOTE]  
> The script will prompt for elevation if not running as admin. Enabling the WSL/Virtual Machine Platform features may require a reboot — the script does **not** reboot automatically. If WSL features were just enabled, reboot manually, then re-run the WSL step (or `wsl --install --web-download -d archlinux`).

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```

## Config locations

| Config | Destination |
|---|---|
| komorebi.json | `~\komorebi.json` |
| whkdrc | `~\.config\whkdrc` |
| nushell env.nu | `%APPDATA%\nushell\env.nu` |
| nushell config.nu | `%APPDATA%\nushell\config.nu` |
| .wslconfig | `~\.wslconfig` |
| wsl.conf | `/etc/wsl.conf` (inside WSL — apply manually) |
| Windows Terminal | merged into `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` |
