#!/usr/bin/env bash
set -Eeuo pipefail

linux_user="$1"
config_root="$2"
relay_path="${3:-}"

[[ $linux_user =~ ^[a-z_][a-z0-9_-]{0,31}$ && $linux_user != root ]] || {
	echo "Invalid Ubuntu username" >&2
	exit 1
}

source /etc/os-release
[[ ${ID:-} == ubuntu ]] || {
	echo "Ubuntu required" >&2
	exit 1
}
[[ -d $config_root ]] || {
	echo "Config payload missing" >&2
	exit 1
}

home_dir="$(getent passwd "$linux_user" | cut -d: -f6)"
[[ -n $home_dir && -d $home_dir ]] || {
	echo "Ubuntu user home missing" >&2
	exit 1
}

chown -R "$linux_user:$linux_user" "$config_root"
find "$config_root" -type d -exec chmod 0755 {} +
find "$config_root" -type f -exec chmod 0644 {} +
chmod 0755 "$config_root/wsl/bootstrap.sh" "$config_root/wsl/dotfiles-setup.sh"
install -d -m 0755 -o "$linux_user" -g "$linux_user" \
	"$home_dir/.config/windows-setup-script" "$home_dir/.local/bin"

backup_and_link() {
	local source="$1" destination="$2"
	if [[ -L $destination && $(readlink "$destination") == "$source" ]]; then
		return
	fi
	if [[ -e $destination || -L $destination ]]; then
		mv "$destination" "$destination.bak-$(date +%Y%m%d-%H%M%S)"
	fi
	ln -s "$source" "$destination"
}

relay_config="$home_dir/.config/windows-setup-script/bitwarden-ssh-agent.zsh"
relay_loader="$home_dir/.zshenv"
relay_link="$home_dir/.local/bin/npiperelay.exe"
if [[ -n $relay_path ]]; then
	[[ -f $relay_path ]] || {
		echo "SSH relay missing" >&2
		exit 1
	}
	backup_and_link "$config_root/wsl/bitwarden-ssh-agent.zsh" "$relay_config"
	backup_and_link "$relay_config" "$relay_loader"
	ln -sfn "$relay_path" "$relay_link"
else
	if [[ -L $relay_loader && $(readlink "$relay_loader") == "$relay_config" ]]; then
		rm -f "$relay_loader"
	fi
	if [[ -L $relay_config && $(readlink "$relay_config") == "$config_root/wsl/bitwarden-ssh-agent.zsh" ]]; then
		rm -f "$relay_config"
	fi
	if [[ -L $relay_link && $(readlink "$relay_link") == /mnt/?/*/AppData/Local/Programs/npiperelay/npiperelay.exe ]]; then
		rm -f "$relay_link"
	fi
fi

wsl_config="$(mktemp /tmp/windots-wsl-conf.XXXXXX)"
trap 'rm -f "${wsl_config:-}"' EXIT
cp "$config_root/wsl/wsl.conf" "$wsl_config"
printf '\n[user]\ndefault=%s\n' "$linux_user" >>"$wsl_config"
if [[ -e /etc/wsl.conf ]] && ! cmp -s "$wsl_config" /etc/wsl.conf; then
	cp -a /etc/wsl.conf "/etc/wsl.conf.bak-$(date +%Y%m%d-%H%M%S)"
fi
install -m 0644 "$wsl_config" /etc/wsl.conf

chown -h "$linux_user:$linux_user" "$relay_config" "$relay_loader" "$relay_link" \
	2>/dev/null || true

echo "Ubuntu integration configured"
