# win-setup

Guided WSL-first setup script for a fresh Windows 11 24H2+ install.

> [!IMPORTANT]  
> Keep this repo at its cloned path. Configs are symlinked where possible, and moving the repo can leave linked configs dangling.  

## What it does

- Elevates itself, then stores state and logs under `%USERPROFILE%\.win-setup`.
- Prompts for categorized installation of Windows software.
- Offers a separate per-tool CLI picker backed by Scoop.
- Installs a chosen Nerd Font with Scoop.
- Enables global Git defaults when needed.
- Optionally installs WSL with Ubuntu and enables my personal configurations.

Software choices include editors, terminals, browsers, communication apps, password managers, productivity apps, developer tools, and Windows utilities. The CLI picker includes Git, GitHub CLI, PowerShell 7, modern search and navigation tools, data processors, terminal utilities, and Git workflow tools.

The personal setup uses `wsl --install`. Reboot afterward, then launch Ubuntu to create the Linux user.

## Usage

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```

## Tests

Run on Windows PowerShell 5.1 or newer:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test.ps1
```
