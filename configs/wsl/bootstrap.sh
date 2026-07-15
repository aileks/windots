#!/usr/bin/env bash
set -euo pipefail

linux_user="$1"
config_root="$2"
relay_path="${3:-}"
home_dir="$(getent passwd "$linux_user" | cut -d: -f6)"

# shellcheck source=/dev/null
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || {
  echo "Ubuntu required" >&2
  exit 1
}
[[ -d $config_root ]] || {
  echo "Config payload missing" >&2
  exit 1
}

chown -R "$linux_user:$linux_user" "$config_root"
find "$config_root" -type d -exec chmod 0755 {} +
find "$config_root" -type f -exec chmod 0644 {} +

export DEBIAN_FRONTEND=noninteractive
apt-get update
# CLI subset from https://github.com/aileks/dotfiles/blob/main/setup.sh
apt-get install -y \
  7zip bat build-essential ca-certificates curl eza fastfetch fd-find ffmpeg \
  fontconfig fzf git iproute2 jq less neovim openssh-client python3 ripgrep shellcheck \
  shfmt socat starship trash-cli unzip wget xz-utils zoxide zsh zsh-antidote

install -d -m 0755 -o "$linux_user" -g "$linux_user" \
  "$home_dir/.config" "$home_dir/.config/windows-setup-script" "$home_dir/.local/bin" "$home_dir/Projects"

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

backup_and_link "$config_root/zsh/zshrc" "$home_dir/.zshrc"
backup_and_link "$config_root/nvim" "$home_dir/.config/nvim"
backup_and_link "$config_root/starship/starship.toml" "$home_dir/.config/starship.toml"
backup_and_link "$config_root/bat" "$home_dir/.config/bat"

btop_config="$home_dir/.config/btop"
if [[ -L $btop_config && $(readlink "$btop_config") == "$config_root/btop" ]]; then
  rm -f "$btop_config"
fi

command -v bat >/dev/null 2>&1 || ln -sfn /usr/bin/batcat "$home_dir/.local/bin/bat"
command -v fd >/dev/null 2>&1 || ln -sfn /usr/bin/fdfind "$home_dir/.local/bin/fd"

if [[ -n $relay_path ]]; then
  [[ -f $relay_path ]] || {
    echo "SSH relay missing" >&2
    exit 1
  }
  backup_and_link "$config_root/wsl/bitwarden-ssh-agent.zsh" \
    "$home_dir/.config/windows-setup-script/bitwarden-ssh-agent.zsh"
  ln -sfn "$relay_path" "$home_dir/.local/bin/npiperelay.exe"
else
  relay_config="$home_dir/.config/windows-setup-script/bitwarden-ssh-agent.zsh"
  if [[ -L $relay_config && $(readlink "$relay_config") == "$config_root/wsl/bitwarden-ssh-agent.zsh" ]]; then
    rm -f "$relay_config"
  fi
  relay_link="$home_dir/.local/bin/npiperelay.exe"
  if [[ -L $relay_link && $(readlink "$relay_link") == /mnt/?/*/AppData/Local/Programs/npiperelay/npiperelay.exe ]]; then
    rm -f "$relay_link"
  fi
fi

if [[ -e /etc/wsl.conf ]] && ! cmp -s "$config_root/wsl/wsl.conf" /etc/wsl.conf; then
  cp -a /etc/wsl.conf "/etc/wsl.conf.bak-$(date +%Y%m%d-%H%M%S)"
fi
install -m 0644 "$config_root/wsl/wsl.conf" /etc/wsl.conf

chown -h "$linux_user:$linux_user" \
  "$home_dir/.zshrc" "$home_dir/.config/nvim" "$home_dir/.config/starship.toml" \
  "$home_dir/.config/bat" "$home_dir/.local/bin"/* 2>/dev/null || true
chsh -s /usr/bin/zsh "$linux_user"

for setting in \
  'init.defaultBranch main' \
  'core.autocrlf input' \
  'pull.rebase true' \
  'rebase.autoStash true' \
  'fetch.prune true' \
  'push.autoSetupRemote true' \
  'merge.conflictStyle zdiff3' \
  'diff.algorithm histogram' \
  'rerere.enabled true' \
  'commit.verbose true' \
  'branch.sort -committerdate' \
  'tag.sort version:refname'; do
  read -r key value <<< "$setting"
  runuser -u "$linux_user" -- env HOME="$home_dir" git config --global "$key" "$value"
done

bat_binary="$(command -v bat || command -v batcat || true)"
[[ -z $bat_binary ]] || runuser -u "$linux_user" -- env HOME="$home_dir" "$bat_binary" cache --build || true
runuser -u "$linux_user" -- env HOME="$home_dir" nvim --headless '+quitall'

echo "Ubuntu configured"
