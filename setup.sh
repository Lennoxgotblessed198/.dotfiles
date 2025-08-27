#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s extglob

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_DIR="$SCRIPT_DIR"
CONFIG_DIR="$HOME/.config"
BACKUP_ROOT="$CONFIG_DIR/.dotfiles_backup_$(date +%Y%m%d-%H%M%S)"
HAD_BACKUP=0
ACTION="${1:-}"  # will be decided by menu if empty; supports: install | update | grub

C_RESET="\033[0m"; C_RED="\033[1;31m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"; C_BLUE="\033[1;34m"; C_CYAN="\033[1;36m"
log()  { printf "%b[INFO]%b %s\n" "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf "%b[ OK ]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%b[WARN]%b %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "%b[FAIL]%b %s\n" "$C_RED" "$C_RESET" "$*"; }

trap 'err "Error at line $LINENO: $BASH_COMMAND"; err "Setup aborted."' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1; }

choose_action() {
	# If ACTION provided via CLI, normalize and return
	case "${ACTION,,}" in
		1|install) ACTION="install" ;;
		2|update)  ACTION="update" ;;
		3|grub|grub-theme|grub_theme) ACTION="grub" ;;
		"") ;;
		*) warn "Unknown action: $ACTION. Defaulting to menu."; ACTION="" ;;
	esac

	if [[ -n "$ACTION" ]]; then
		return 0
	fi

	printf "%b%s%b\n" "$C_CYAN" "Select an action:" "$C_RESET"
	printf "  1) Install (packages + deploy configs)\n"
	printf "  2) Update configs (no package installs)\n"
	printf "  3) Install GRUB theme only\n"
	printf "%b[PROMPT]%b Enter choice [1-3]: " "$C_YELLOW" "$C_RESET"
	read -r choice
	case "$choice" in
		1) ACTION="install" ;;
		2) ACTION="update" ;;
		3) ACTION="grub" ;;
		*) warn "Invalid choice. Defaulting to Install."; ACTION="install" ;;
	esac
}

preflight() {

	if [[ $EUID -eq 0 ]]; then
		warn "Running as root: configs will target /root. It's recommended to run as your user."
	else
		# Request sudo only when needed
		if [[ "$ACTION" == "install" || "$ACTION" == "grub" ]]; then
			printf "%b[AUTH]%b Requesting administrator privileges (sudo) for this action...\n" "$C_BLUE" "$C_RESET"
			if sudo -v; then
				ok "Sudo credentials cached"
			else
				err "Sudo is required for this action. Aborting."
				exit 1
			fi
		fi
	fi

	printf "%b%s%b\n" "$C_CYAN" "This is an experimental setup script tailored for Arch-based systems." "$C_RESET"
	printf "%b%s%b\n" "$C_CYAN" "For best results, you may also apply the files manually; this script automates those steps safely." "$C_RESET"

	if [[ "$ACTION" == "update" ]]; then
		printf "%b[PROMPT]%b Proceed with IN-PLACE config update (no package installation)? [y/N]: " "$C_YELLOW" "$C_RESET"
	elif [[ "$ACTION" == "grub" ]]; then
		printf "%b[PROMPT]%b Proceed with GRUB theme installation? [y/N]: " "$C_YELLOW" "$C_RESET"
	else
		printf "%b[PROMPT]%b Proceed with system update and configuration deployment? [y/N]: " "$C_YELLOW" "$C_RESET"
	fi
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

# Compare two files; return 0 if identical, 1 if different or missing
files_identical() {
	local a="$1" b="$2"
	[[ -f "$a" && -f "$b" ]] || return 1
	cmp -s "$a" "$b" 2>/dev/null && return 0 || return 1
}

# Update copy for a single file: copy if missing or different, backup if replacing
update_copy_file() {
	local src="$1" dest="$2"
	if [[ ! -e "$dest" ]]; then
		mkdir -p "$(dirname "$dest")"
		install -m 0644 "$src" "$dest"
		ok "Added: $dest"
		return 0
	fi
	if files_identical "$src" "$dest"; then
		log "Unchanged: $dest"
		return 0
	fi
	backup_path "$dest"
	mkdir -p "$(dirname "$dest")"
	install -m 0644 "$src" "$dest"
	ok "Updated: $dest"
}

# Update copy for a directory: copy files that are missing or changed (no deletions)
update_copy_dir() {
	local src="$1" dest="$2"
	[[ -d "$src" ]] || { warn "Source directory missing: $src"; return 0; }
	mkdir -p "$dest"
	local f rel to
	while IFS= read -r -d '' f; do
		rel="${f#"$src/"}"
		to="$dest/$rel"
		update_copy_file "$f" "$to"
	done < <(find "$src" -type f -print0)
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

# In-place update of configs: only changed/missing files are copied; no mass backups.
update_configs() {
	ensure_dirs

	# btop
	if [[ -f "$REPO_DIR/btop/btop.conf" ]]; then
		update_copy_dir "$REPO_DIR/btop" "$CONFIG_DIR/btop"
		ok "Updated btop config"
	fi

	# cava
	if [[ -f "$REPO_DIR/cava/config" ]]; then
		update_copy_dir "$REPO_DIR/cava" "$CONFIG_DIR/cava"
		ok "Updated cava config"
	fi

	# kitty
	if [[ -f "$REPO_DIR/kitty/kitty.conf" ]]; then
		update_copy_dir "$REPO_DIR/kitty" "$CONFIG_DIR/kitty"
		ok "Updated kitty config"
	fi

	# hypr, waybar, swaync
	if [[ -d "$REPO_DIR/hypr" ]]; then update_copy_dir "$REPO_DIR/hypr" "$CONFIG_DIR/hypr"; ok "Updated hypr config"; fi
	if [[ -d "$REPO_DIR/waybar" ]]; then update_copy_dir "$REPO_DIR/waybar" "$CONFIG_DIR/waybar"; ok "Updated waybar config"; fi
	if [[ -d "$REPO_DIR/swaync" ]]; then update_copy_dir "$REPO_DIR/swaync" "$CONFIG_DIR/swaync"; ok "Updated swaync config"; fi

	# rofi
	if [[ -d "$REPO_DIR/rofi" ]]; then
		update_copy_dir "$REPO_DIR/rofi" "$CONFIG_DIR/rofi"
		make_exec_in "$CONFIG_DIR/rofi/scripts"
		make_exec_in "$CONFIG_DIR/rofi/applets/bin"
		ok "Updated rofi config"
	fi

	# waybar scripts executable
	make_exec_in "$CONFIG_DIR/waybar/scripts"

	# zsh
	if [[ -f "$REPO_DIR/zsh/zshrc" ]]; then
		update_copy_file "$REPO_DIR/zsh/zshrc" "$HOME/.zshrc"
		ok "Updated .zshrc"
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

	# If called with "force", skip prompt
	local force="${1:-}"
	if [[ "$force" != "force" ]]; then
		printf "%b[PROMPT]%b Are you using GRUB as your boot manager and want to install the provided theme now? [y/N]: " "$C_YELLOW" "$C_RESET"
		read -r reply
		case "$reply" in
			[yY]|[yY][eE][sS]) ;;
			*) log "Skipping GRUB theme installation"; return 0 ;;
		esac
	fi

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
	return 0
}

main() {
	log "Starting dotfiles setup from: $REPO_DIR (action: $ACTION)"
	case "$ACTION" in
		update)
			update_configs
			post_steps
			;;
		grub)
			maybe_install_grub_theme force
			;;
		install|*)
			install_pacman_packages
			install_aur_packages
			deploy_configs
			post_steps
			;;
	 esac

	if [[ "$HAD_BACKUP" -eq 1 ]]; then
		warn "Existing configs were backed up to: $BACKUP_ROOT"
	fi
	ok "Action completed successfully"
}

choose_action
preflight
main "$@"