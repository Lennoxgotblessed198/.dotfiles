#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s extglob

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_DIR="$SCRIPT_DIR"
CONFIG_DIR="$HOME/.config"
BACKUP_ROOT="$CONFIG_DIR/.dotfiles_backup_$(date +%Y%m%d-%H%M%S)"
HAD_BACKUP=0

C_RESET="\033[0m"; C_RED="\033[1;31m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"; C_BLUE="\033[1;34m"; C_CYAN="\033[1;36m"
log()  { printf "%b[INFO]%b %s\n" "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf "%b[ OK ]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%b[WARN]%b %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "%b[FAIL]%b %s\n" "$C_RED" "$C_RESET" "$*"; }

trap 'err "Error at line $LINENO: $BASH_COMMAND"; err "Setup aborted."' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1; }

preflight() {

	if [[ $EUID -eq 0 ]]; then
		warn "Running as root: configs will target /root. It's recommended to run as your user."
	else
		printf "%b[AUTH]%b Requesting administrator privileges (sudo) for package installation...\n" "$C_BLUE" "$C_RESET"
		if sudo -v; then
			ok "Sudo credentials cached"
		else
			err "Sudo is required for installation. Aborting."
			exit 1
		fi
	fi

	printf "%b%s%b\n" "$C_CYAN" "This is an experimental setup script tailored for Arch-based systems." "$C_RESET"
	printf "%b%s%b\n" "$C_CYAN" "For best results, you may also apply the files manually; this script automates those steps safely." "$C_RESET"

	printf "%b[PROMPT]%b Proceed with system update and configuration deployment? [y/N]: " "$C_YELLOW" "$C_RESET"
	read -r reply
	case "$reply" in
		[yY]|[yY][eE][sS]) ;;
		*) warn "Aborted by user."; exit 0 ;;
	esac

	log "Starting in..."
	for n in 3 2 1; do log "$n..."; sleep 1; done
}

ensure_dirs() {
	mkdir -p "$CONFIG_DIR"
}

backup_path() {
	local path="$1"
	[[ -e "$path" || -L "$path" ]] || return 0
	mkdir -p "$BACKUP_ROOT"
	local base
	base="$(basename "$path")"
	local dest="$BACKUP_ROOT/$base"
	log "Backing up: $path -> $dest"
	mv -f "$path" "$dest"
	HAD_BACKUP=1
}

copy_file() {
	local src="$1" dest="$2"
	backup_path "$dest"
	mkdir -p "$(dirname "$dest")"
	install -m 0644 "$src" "$dest"
}

copy_dir() {
	local src="$1" dest="$2"
	backup_path "$dest"
	mkdir -p "$(dirname "$dest")"
	cp -a "$src" "$dest"
}

make_exec_in() {
	local dir="$1"
	if [[ -d "$dir" ]]; then
		find "$dir" -type f -name "*.sh" -exec chmod +x {} + || true
	fi
}

install_pacman_packages() {
	if require_cmd pacman; then
		log "Updating system packages (pacman)"
		sudo pacman -Syu --noconfirm
		ok "System updated"

		local pkgs=(
			git
			base-devel
			flatpak
			discover
			hyprland
			hyprpaper
			swaync
			waybar
			rofi
			cava
			btop
			kitty
			zsh
			ttf-jetbrains-mono-nerd
			playerctl
			jq
			wl-clipboard
			grim
			slurp
			brightnessctl
		)
		log "Installing packages: ${pkgs[*]}"
		sudo pacman -S --needed --noconfirm "${pkgs[@]}"
		ok "Base packages installed"
	else
		err "This setup currently supports Arch-based systems (pacman) only."
		err "Detected no pacman. Aborting."
		exit 1
	fi
}

ensure_yay() {
	if require_cmd yay; then
		ok "yay already installed"
		return
	fi
	log "Installing yay (AUR helper)"
	local tmpdir
	tmpdir="$(mktemp -d)"
	pushd "$tmpdir" >/dev/null
	sudo pacman -S --needed --noconfirm git base-devel
	git clone https://aur.archlinux.org/yay.git
	cd yay
	makepkg -si --noconfirm
	popd >/dev/null
	rm -rf "$tmpdir"
	ok "yay installed"
}

install_aur_packages() {
	ensure_yay
	local aur_pkgs=(
		cbonsai
		pipes.sh
	)
	log "Installing AUR packages: ${aur_pkgs[*]}"
	if yay -S --needed --noconfirm "${aur_pkgs[@]}"; then
		ok "AUR packages installed"
	else
		warn "Some AUR packages failed to install; continuing"
	fi
}

deploy_configs() {
	ensure_dirs

	# btop
	if [[ -f "$REPO_DIR/btop/btop.conf" ]]; then
		copy_dir "$REPO_DIR/btop" "$CONFIG_DIR/btop"
		ok "Deployed btop config"
	fi

	# cava
	if [[ -f "$REPO_DIR/cava/config" ]]; then
		copy_dir "$REPO_DIR/cava" "$CONFIG_DIR/cava"
		ok "Deployed cava config"
	fi

	# kitty
	if [[ -f "$REPO_DIR/kitty/kitty.conf" ]]; then
		copy_dir "$REPO_DIR/kitty" "$CONFIG_DIR/kitty"
		ok "Deployed kitty config"
	fi

	# hypr, waybar, swaync
	if [[ -d "$REPO_DIR/hypr" ]]; then copy_dir "$REPO_DIR/hypr" "$CONFIG_DIR/hypr"; ok "Deployed hypr config"; fi
	if [[ -d "$REPO_DIR/waybar" ]]; then copy_dir "$REPO_DIR/waybar" "$CONFIG_DIR/waybar"; ok "Deployed waybar config"; fi
	if [[ -d "$REPO_DIR/swaync" ]]; then copy_dir "$REPO_DIR/swaync" "$CONFIG_DIR/swaync"; ok "Deployed swaync config"; fi

	# rofi
	if [[ -d "$REPO_DIR/rofi" ]]; then
		copy_dir "$REPO_DIR/rofi" "$CONFIG_DIR/rofi"
		make_exec_in "$CONFIG_DIR/rofi/scripts"
		make_exec_in "$CONFIG_DIR/rofi/applets/bin"
		ok "Deployed rofi config"
	fi

	# waybar scripts executable
	make_exec_in "$CONFIG_DIR/waybar/scripts"

	# zsh
	if [[ -f "$REPO_DIR/zsh/zshrc" ]]; then
		copy_file "$REPO_DIR/zsh/zshrc" "$HOME/.zshrc"
		ok "Installed .zshrc"
	fi
}

post_steps() {
	# Refresh font cache if fonts were installed
	if fc-cache -V >/dev/null 2>&1; then
		log "Refreshing font cache"
		if fc-cache -f; then
			ok "Font cache refreshed"
		else
			warn "Font cache refresh failed"
		fi
	fi
}

# Optionally install GRUB theme provided in this repo
maybe_install_grub_theme() {
	local theme_dir="$REPO_DIR/boot_manager/LainGrubTheme-1.0.1"
	local install_sh="$theme_dir/install.sh"
	local patch_sh="$theme_dir/patch_entries.sh"

	printf "%b[PROMPT]%b Are you using GRUB as your boot manager and want to install the provided theme now? [y/N]: " "$C_YELLOW" "$C_RESET"
	read -r reply
	case "$reply" in
		[yY]|[yY][eE][sS])
			if [[ ! -d "$theme_dir" ]]; then
				warn "GRUB theme directory not found: $theme_dir"
				return 0
			fi

			# Make sure scripts are executable and run them with sudo
			[[ -f "$install_sh" ]] || { warn "Missing: $install_sh"; return 0; }
			[[ -f "$patch_sh" ]] || { warn "Missing: $patch_sh"; return 0; }
			chmod +x "$install_sh" "$patch_sh" 2>/dev/null || true

			# Best-effort detection to inform the user (does not block)
			if ! require_cmd grub-install && ! pacman -Q grub >/dev/null 2>&1 && [[ ! -d /boot/grub ]]; then
				warn "GRUB may not be installed or detected on this system. Proceeding anyway as requested."
			fi

			log "Running GRUB theme installer (sudo may prompt for your password)"
			if sudo bash "$install_sh"; then
				ok "Theme installation script completed"
			else
				err "Theme installation failed"
				return 1
			fi

			log "Patching GRUB entries"
			if sudo bash "$patch_sh"; then
				ok "GRUB entries patched"
			else
				warn "Patching GRUB entries failed"
			fi
			;;
		*)
			log "Skipping GRUB theme installation"
			;;
	esac
}

main() {
	log "Starting dotfiles setup from: $REPO_DIR"
	install_pacman_packages
	install_aur_packages
	deploy_configs
	post_steps
	maybe_install_grub_theme
	if [[ "$HAD_BACKUP" -eq 1 ]]; then
		warn "Existing configs were backed up to: $BACKUP_ROOT"
	fi
	ok "Setup completed successfully"
}

preflight
main "$@"