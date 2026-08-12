#!/usr/bin/env bash
set -Eeuo pipefail

linux_user="$1"
config_root="$2"
relay_path="${3:-}"

[[ $linux_user =~ ^[a-z_][a-z0-9_-]{0,31}$ && $linux_user != root ]] || {
  echo "Invalid Arch Linux username" >&2
  exit 1
}

# shellcheck source=/dev/null
source /etc/os-release
[[ ${ID:-} == arch ]] || {
  echo "Arch Linux required" >&2
  exit 1
}
[[ -d $config_root ]] || {
  echo "Config payload missing" >&2
  exit 1
}

home_dir="$(getent passwd "$linux_user" | cut -d: -f6)"
[[ -n $home_dir && -d $home_dir ]] || {
  echo "Arch Linux user home missing" >&2
  exit 1
}

readonly -a official_packages=(
  7zip
  bat
  base-devel
  btop
  curl
  eza
  fastfetch
  fd
  ffmpeg
  fzf
  git
  iproute2
  jq
  less
  lua
  man-db
  neovim
  nvm
  openssh
  podman
  podman-compose
  podman-docker
  python
  ripgrep
  rsync
  shellcheck
  shfmt
  socat
  starship
  tmux
  trash-cli
  unzip
  uv
  wget
  xz
  zip
  zoxide
  zsh
)

readonly -a aur_packages=(
  paru-bin
  zsh-antidote
  tmux-sessionizer-bin
  win32yank-bin
)

pacman -Syu --needed --noconfirm "${official_packages[@]}"
usermod --append --groups wheel "$linux_user"
install -d -m 0755 /etc/sudoers.d
printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel
visudo --check --file=/etc/sudoers.d/10-wheel >/dev/null

chown -R "$linux_user:$linux_user" "$config_root"
find "$config_root" -type d -exec chmod 0755 {} +
find "$config_root" -type f -exec chmod 0644 {} +
install -d -m 0755 -o "$linux_user" -g "$linux_user" \
  "$home_dir/.config" "$home_dir/.config/windows-setup-script" \
  "$home_dir/.local/bin" "$home_dir/Projects"

aur_root="$(mktemp -d /tmp/windots-aur.XXXXXX)"
chown "$linux_user:$linux_user" "$aur_root"
cleanup() {
  [[ -z ${aur_root:-} || ! -d $aur_root ]] || rm -rf -- "$aur_root"
}
trap cleanup EXIT

install_aur_package() {
  local package="$1" checkout="$aur_root/$1"
  local -a package_files=()

  pacman -Qq "$package" >/dev/null 2>&1 && return
  runuser -u "$linux_user" -- env HOME="$home_dir" \
    git clone --depth 1 "https://aur.archlinux.org/$package.git" "$checkout"

  if [[ -t 0 && -t 1 && -r /dev/tty ]]; then
    printf '\nReviewing %s PKGBUILD. Quit the pager to continue.\n' "$package" >/dev/tty
    runuser -u "$linux_user" -- env HOME="$home_dir" less "$checkout/PKGBUILD" </dev/tty >/dev/tty
  fi

  # shellcheck disable=SC2016
  runuser -u "$linux_user" -- env HOME="$home_dir" \
    bash -c 'cd "$1" && makepkg --cleanbuild --noconfirm' _ "$checkout"
  mapfile -d '' package_files < <(
    find "$checkout" -maxdepth 1 -type f -name '*.pkg.tar.zst' -print0
  )
  ((${#package_files[@]} > 0)) || {
    echo "AUR package build produced no package: $package" >&2
    return 1
  }
  pacman -U --needed --noconfirm "${package_files[@]}"
}

for package in "${aur_packages[@]}"; do
  install_aur_package "$package"
done

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
backup_and_link "$config_root/tmux" "$home_dir/.config/tmux"
backup_and_link "$config_root/btop" "$home_dir/.config/btop"
backup_and_link "$config_root/fastfetch" "$home_dir/.config/fastfetch"
backup_and_link "$config_root/starship/starship.toml" "$home_dir/.config/starship.toml"
backup_and_link "$config_root/bat" "$home_dir/.config/bat"

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

wsl_config="$(mktemp /tmp/windots-wsl-conf.XXXXXX)"
cp "$config_root/wsl/wsl.conf" "$wsl_config"
printf '\n[user]\ndefault=%s\n' "$linux_user" >>"$wsl_config"
if [[ -e /etc/wsl.conf ]] && ! cmp -s "$wsl_config" /etc/wsl.conf; then
  cp -a /etc/wsl.conf "/etc/wsl.conf.bak-$(date +%Y%m%d-%H%M%S)"
fi
install -m 0644 "$wsl_config" /etc/wsl.conf
rm -f "$wsl_config"

runuser -u "$linux_user" -- env HOME="$home_dir" NVM_DIR="$home_dir/.nvm" bash -c '
  set -e
  source /usr/share/nvm/init-nvm.sh
  nvm install --lts
  nvm alias default "lts/*"
  nvm use default
  if command -v corepack >/dev/null 2>&1; then
    corepack enable pnpm
    corepack install --global pnpm@latest
  else
    npm install --global pnpm
  fi
'

# Linger starts the user manager reliably when WSL boots, which keeps the
# rootless Podman socket available even before the first interactive shell.
install -Dm0644 /dev/null "/var/lib/systemd/linger/$linux_user"
systemctl --global enable podman.socket >/dev/null
runuser -u "$linux_user" -- env HOME="$home_dir" tms config --paths "$home_dir/Projects"
chsh -s /usr/bin/zsh "$linux_user"

chown -h "$linux_user:$linux_user" \
  "$home_dir/.zshrc" "$home_dir/.config/nvim" "$home_dir/.config/tmux" \
  "$home_dir/.config/btop" "$home_dir/.config/fastfetch" \
  "$home_dir/.config/starship.toml" "$home_dir/.config/bat" \
  "$home_dir/.local/bin"/* 2>/dev/null || true

runuser -u "$linux_user" -- env HOME="$home_dir" bat cache --build
runuser -u "$linux_user" -- env HOME="$home_dir" nvim --headless '+quitall'
runuser -u "$linux_user" -- env HOME="$home_dir" podman info >/dev/null
runuser -u "$linux_user" -- env HOME="$home_dir" NVM_DIR="$home_dir/.nvm" bash -c '
  set -e
  source /usr/share/nvm/init-nvm.sh
  nvm use default >/dev/null
  node --version
  pnpm --version
'

for command in bat btop docker eza fastfetch fd fzf nvim paru podman rg starship tms tmux trash uv win32yank.exe zoxide zsh; do
  command -v "$command" >/dev/null || {
    echo "Required command missing after bootstrap: $command" >&2
    exit 1
  }
done

echo "Arch Linux configured"
