# Windows Setup

Forced to use Windows so I might as well make it usable. Windows 11 24H2+ only.

> [!IMPORTANT]
> Keep this repository at its cloned path. Configs are symlinked where possible. Moving the repository leaves those links dangling.

## Flow

1. Run `setup.ps1` from Windows PowerShell.
2. The script elevates itself.
3. If WSL or Virtual Machine Platform is disabled, the script offers to enable them and reboot. A per-user `RunOnce` entry resumes setup after login.
4. Read the disclaimer and confirm with `Continue with setup?`.
5. Review the preselected optional software in the terminal UI.
6. The script installs software, applies Windows tweaks, installs Ubuntu, pauses for Ubuntu user creation, and provisions the Linux environment.
7. Reboot again when requested.

```powershell
Set-ExecutionPolicy Bypass -Scope Process
.\setup.ps1
```

## Windows

- Enable long paths, four-way symlink evaluation, and Sudo for Windows in `normal` mode.
- Show extensions and hidden files; hide recent/frequent files and sync-provider ads.
- Keep the centered, auto-hidden taskbar; remove Search and Widgets from it.
- Disable Widgets, cloud/web search, consumer content, suggestions, tips, and tailored experiences.
- Set diagnostic data to `0`; disable opt-in UI, extended logs/dumps, feedback prompts, advertising ID, activity upload, speech/input personalization, and location services.
- Disable Recall snapshots and remove the Recall optional component when present.
- Keep local clipboard history while disabling cross-device clipboard sync.
- Activate Ultimate Performance.

Original registry values are recorded once in `%USERPROFILE%\.win-setup\registry-backup.json`. The script assumes the installed Windows edition honors diagnostic data level `0` as a complete opt-out.

## WSL

- Installs Ubuntu 26.04
- Installs build tools, curl, git, certificates, and unzip.
- Prompts for git setup.
- Sets zsh as default shell.
- Installs modern utilities: socat, ripgrep, fzf, fastfetch, bat, eza, zoxide, fd, jq, and Starship.
- `~/projects` for Linux-hosted repositories.

## Configs and state

Existing files are timestamp-backed up before replacement. Checked-in configs are linked into Windows and WSL. Windows Terminal settings are backed up before their scheme/default profile merge.

State and logs:

- `%USERPROFILE%\.win-setup\state.json`
- `%USERPROFILE%\.win-setup\setup.log`
- `%USERPROFILE%\.win-setup\registry-backup.json`

Successful actions are skipped on rerun. Changing files under `data/` or `configs/`, or changing optional selections reapplies the setup. Delete `state.json` to force a complete rerun.

