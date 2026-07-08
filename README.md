# win-setup

Guided WSL-first setup script for a fresh Windows 11 24H2+ install.

> [!IMPORTANT]  
> Keep this repo at its cloned path. Configs are symlinked where possible, and moving the repo can leave linked configs dangling.  

## What it does

- Elevates itself, then stores state and logs under `%USERPROFILE%\.win-setup`.
- Prompts for categorized installation of Windows software.
- Installs a chosen Nerd Font with Scoop.
- Enables global Git defaults when needed.
- Optionally enables my personal configurations.

## Usage

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```

