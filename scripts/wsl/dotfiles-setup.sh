#!/usr/bin/env bash

setup_dotfiles() (
	set -Eeuo pipefail

	readonly repository_url="https://github.com/aileks/dotfiles.git"
	readonly dotfiles_dir="$HOME/.dotfiles"

	if ! command -v git >/dev/null; then
		sudo apt update
		sudo env DEBIAN_FRONTEND=noninteractive apt install -y git
	fi

	if [[ -e $dotfiles_dir || -L $dotfiles_dir ]]; then
		[[ -d $dotfiles_dir/.git ]] || {
			echo "$dotfiles_dir exists and is not a Git repository" >&2
			return 1
		}
		remote_url="$(git -C "$dotfiles_dir" remote get-url origin)"
		[[ $remote_url == "$repository_url" || $remote_url == *aileks/dotfiles* ]] || {
			echo "$dotfiles_dir is not the expected dotfiles repository" >&2
			return 1
		}
	else
		git clone "$repository_url" "$dotfiles_dir"
	fi

	"$dotfiles_dir/setup.sh"

	if [[ -e $HOME/.local/bin/npiperelay.exe ]] && ! command -v socat >/dev/null; then
		sudo env DEBIAN_FRONTEND=noninteractive apt install -y socat
	fi
)

if setup_dotfiles; then
	printf '\nDotfiles setup complete.\n'
else
	setup_status=$?
	printf '\nDotfiles setup failed with exit %d.\n' "$setup_status" >&2
fi

if command -v zsh >/dev/null; then
	exec zsh -l
fi
exec bash -l
