#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s extglob

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_DIR="$SCRIPT_DIR"
CONFIG_DIR="$HOME/.config"
BACKUP_ROOT="$CONFIG_DIR/.dotfiles_backup_$(date +%Y%m%d-%H%M%S)"
HAD_BACKUP=0
ACTION="${1:-}"
THEMES_DIR="$REPO_DIR/themes"
CHOSEN_COLOR_PATH=""
GRUB_THEMES_BASE="$REPO_DIR/boot_manager"
GRUB_SELECTED_PATH=""

C_RESET="\033[0m"; C_RED="\033[1;31m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"; C_BLUE="\033[1;34m"; C_CYAN="\033[1;36m"
log()  { printf "%b[INFO]%b %s\n" "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf "%b[ OK ]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf "%b[WARN]%b %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "%b[FAIL]%b %s\n" "$C_RED" "$C_RESET" "$*"; }

trap 'err "Error at line $LINENO: $BASH_COMMAND"; err "Setup aborted."' ERR

require_cmd() { command -v "$1" >/dev/null 2>&1; }

choose_action() {

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

	case "$ACTION" in
		install|update)
			if [[ -z "$CHOSEN_COLOR_PATH" ]]; then
				choose_color
			fi
			;;
		grub)
			if [[ -z "$GRUB_SELECTED_PATH" ]]; then
				choose_grub_theme
			fi
			;;
	esac

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

find_colors() {
	local colors=()
	if [[ -d "$THEMES_DIR" ]]; then
		while IFS= read -r -d '' d; do
			colors+=("$(basename "$d")")
		done < <(find "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
	fi
	# Fallback: top-level color dirs (exclude known base dirs)
	if [[ ${#colors[@]} -eq 0 ]]; then
		while IFS= read -r -d '' d; do
			local name; name="$(basename "$d")"
			case "$name" in
				.git|themes|zsh|boot_manager|btop|cava|kitty|hypr|waybar|swaync|rofi) continue ;;
			esac
			colors+=("$name")
		done < <(find "$REPO_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
	fi
	echo "${colors[@]}"
}

choose_color() {
	local colors=( $(find_colors) )
	if [[ ${#colors[@]} -eq 0 ]]; then
		warn "No theme color folders found. Using base configs."
		CHOSEN_COLOR_PATH=""
		return 0
	fi
	printf "%b%s%b\n" "$C_CYAN" "Available color themes:" "$C_RESET"
	local i=1
	for c in "${colors[@]}"; do printf "  %d) %s\n" "$i" "$c"; ((i++)); done
	printf "%b[INPUT]%b Select color [1-%d]: " "$C_YELLOW" "$C_RESET" "${#colors[@]}"
	local idx; read -r idx
	if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#colors[@]} )); then
		warn "Invalid selection; using base configs"
		CHOSEN_COLOR_PATH=""
		return 0
	fi
	local chosen="${colors[idx-1]}"
	if [[ -d "$THEMES_DIR/$chosen" ]]; then
		CHOSEN_COLOR_PATH="$THEMES_DIR/$chosen"
	else
		CHOSEN_COLOR_PATH="$REPO_DIR/$chosen"
	fi
	ok "Selected theme: $(basename "$CHOSEN_COLOR_PATH")"
}

find_grub_themes() {
	local candidates=()

	if [[ -d "$GRUB_THEMES_BASE" ]]; then
		while IFS= read -r -d '' script; do
			local dir; dir="$(dirname "$script")"
			candidates+=("$dir")
		done < <(find "$GRUB_THEMES_BASE" -type f -name "install.sh" -print0 2>/dev/null)
	fi
	echo "${candidates[@]}"
}

choose_grub_theme() {
	local themes=( $(find_grub_themes) )
	if [[ ${#themes[@]} -eq 0 ]]; then
		warn "No GRUB themes with install.sh found under: $GRUB_THEMES_BASE"
		GRUB_SELECTED_PATH=""
		return 0
	fi
	printf "%b%s%b\n" "$C_CYAN" "Available GRUB themes:" "$C_RESET"
	local i=1
	for p in "${themes[@]}"; do printf "  %d) %s\n" "$i" "$(basename "$p")"; ((i++)); done
	printf "%b[INPUT]%b Select GRUB theme [1-%d]: " "$C_YELLOW" "$C_RESET" "${#themes[@]}"
	local idx; read -r idx
	if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#themes[@]} )); then
		warn "Invalid selection; skipping GRUB theme selection"
		GRUB_SELECTED_PATH=""
		return 0
	fi
	GRUB_SELECTED_PATH="${themes[idx-1]}"
	ok "Selected GRUB theme: $(basename "$GRUB_SELECTED_PATH")"
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
	if [[ "$dest" == *.sh ]]; then
		install -m 0755 "$src" "$dest"
	else
		install -m 0644 "$src" "$dest"
	fi
}

copy_dir() {
	local src="$1" dest="$2"
	backup_path "$dest"
	mkdir -p "$(dirname "$dest")"
	cp -a "$src" "$dest"

	if [[ -d "$dest" ]]; then
		find "$dest" -type f -name "*.sh" -exec chmod +x {} + || true
	fi
}

files_identical() {
	local a="$1" b="$2"
	[[ -f "$a" && -f "$b" ]] || return 1
	cmp -s "$a" "$b" 2>/dev/null && return 0 || return 1
}

# Find the repository zshrc file supporting several common layouts
find_repo_zshrc() {
	local candidates=(
		"$REPO_DIR/zsh/.zshrc"
		"$REPO_DIR/zsh/zshrc"
		"$REPO_DIR/.zshrc"
		"$REPO_DIR/zshrc"
	)
	local f
	for f in "${candidates[@]}"; do
		if [[ -f "$f" ]]; then
			printf '%s' "$f"
			return 0
		fi
	done
	return 1
}

# Find a theme-specific zshrc based on the selected color theme
find_theme_zshrc() {
	local base="$CHOSEN_COLOR_PATH"
	[[ -n "$base" && -d "$base" ]] || return 1
	local candidates=(
		"$base/zsh/.zshrc"
		"$base/.zshrc"
		"$base/zsh/zshrc"
		"$base/zshrc"
	)
	local f
	for f in "${candidates[@]}"; do
		if [[ -f "$f" ]]; then
			printf '%s' "$f"
			return 0
		fi
	done
	return 1
}

update_copy_file() {
	local src="$1" dest="$2"
	if [[ ! -e "$dest" ]]; then
		mkdir -p "$(dirname "$dest")"
		if [[ "$dest" == *.sh ]]; then
			install -m 0755 "$src" "$dest"
		else
			install -m 0644 "$src" "$dest"
		fi
		ok "Added: $dest"
		return 0
	fi
	if files_identical "$src" "$dest"; then
		log "Unchanged: $dest"
		return 0
	fi
	backup_path "$dest"
	mkdir -p "$(dirname "$dest")"
	if [[ "$dest" == *.sh ]]; then
		install -m 0755 "$src" "$dest"
	else
		install -m 0644 "$src" "$dest"
	fi
	ok "Updated: $dest"
}

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

ensure_zsh_installed() {
	if require_cmd zsh; then return 0; fi
	if [[ "$ACTION" != "install" ]]; then
		warn "zsh not found; skipping install during update"
		return 0
	fi
	if require_cmd pacman; then
		log "Installing zsh"
		sudo pacman -S --needed --noconfirm zsh
		ok "zsh installed"
	else
		err "pacman not available; cannot install zsh"
		return 1
	fi
}

set_default_shell_zsh() {
	local zsh_path
	zsh_path="$(command -v zsh || true)"
	[[ -n "$zsh_path" ]] || { warn "zsh binary not found; cannot set default shell"; return 0; }

	if ! grep -q "^$zsh_path$" /etc/shells 2>/dev/null; then
		log "Registering $zsh_path in /etc/shells"
		echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null || warn "Could not add $zsh_path to /etc/shells"
	fi

	local target_user="$USER"
	if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" ]]; then
		target_user="$SUDO_USER"
	fi
	local current_shell
	current_shell="$(getent passwd "$target_user" | cut -d: -f7 || echo "${SHELL:-}")"
	if [[ "$current_shell" != "$zsh_path" ]]; then
		log "Changing default shell for $target_user to $zsh_path"
		if [[ "$target_user" == "$USER" ]]; then
			chsh -s "$zsh_path" "$target_user" && ok "Default shell set to zsh"
		else
			sudo chsh -s "$zsh_path" "$target_user" && ok "Default shell set to zsh for $target_user"
		fi
	else
		log "Default shell already zsh for $target_user"
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

	make_exec_in "$CONFIG_DIR/waybar/scripts"

}

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

	make_exec_in "$CONFIG_DIR/waybar/scripts"

}

deploy_color_configs() {
	ensure_dirs
	local base="$1"
	[[ -n "$base" && -d "$base" ]] || { warn "Theme path invalid: $base"; return 0; }
	local comps=(hypr waybar rofi swaync kitty btop cava swaylock swaybg sway)
	for c in "${comps[@]}"; do
		if [[ -d "$base/$c" ]]; then
			copy_dir "$base/$c" "$CONFIG_DIR/$c"
			ok "Deployed $c (theme: $(basename "$base"))"
		fi
	done
	make_exec_in "$CONFIG_DIR/rofi/scripts"
	make_exec_in "$CONFIG_DIR/rofi/applets/bin"
	make_exec_in "$CONFIG_DIR/waybar/scripts"
}

update_color_configs() {
	ensure_dirs
	local base="$1"
	[[ -n "$base" && -d "$base" ]] || { warn "Theme path invalid: $base"; return 0; }
	local comps=(hypr waybar rofi swaync kitty btop cava swaylock swaybg sway)
	for c in "${comps[@]}"; do
		if [[ -d "$base/$c" ]]; then
			update_copy_dir "$base/$c" "$CONFIG_DIR/$c"
			ok "Updated $c (theme: $(basename "$base"))"
		fi
	done
	make_exec_in "$CONFIG_DIR/rofi/scripts"
	make_exec_in "$CONFIG_DIR/rofi/applets/bin"
	make_exec_in "$CONFIG_DIR/waybar/scripts"
}

deploy_base_configs() {

	ensure_zsh_installed || true
	if [[ "$ACTION" == "install" ]]; then
		set_default_shell_zsh || true
	fi
	local DEST_ZSHRC="$HOME/.zshrc"
	local SRC_ZSHRC=""
	if SRC_ZSHRC="$(find_theme_zshrc)"; then
		log "Using theme zshrc: $SRC_ZSHRC"
	elif SRC_ZSHRC="$(find_repo_zshrc)"; then
		log "Using repo zshrc: $SRC_ZSHRC"
	else
		warn "No zshrc found in theme or repo; skipping ~/.zshrc refresh"
		SRC_ZSHRC=""
	fi
	if [[ -n "$SRC_ZSHRC" ]]; then
		update_copy_file "$SRC_ZSHRC" "$DEST_ZSHRC"
		if cmp -s "$SRC_ZSHRC" "$DEST_ZSHRC" 2>/dev/null; then
			ok "Ensured ~/.zshrc"
		else
			warn "~/.zshrc differs after copy; manual check recommended"
		fi
	fi
	if [[ -d "$REPO_DIR/boot_manager" ]]; then
		update_copy_dir "$REPO_DIR/boot_manager" "$CONFIG_DIR/boot_manager"
		ok "Ensured boot_manager"
	fi
}

post_steps() {

	if fc-cache -V >/dev/null 2>&1; then
		log "Refreshing font cache"
		if fc-cache -f; then
			ok "Font cache refreshed"
		else
			warn "Font cache refresh failed"
		fi
	fi
}

maybe_install_grub_theme() {
	local base_dir
	base_dir="${1:-$GRUB_SELECTED_PATH}"
	[[ -n "$base_dir" ]] || { warn "No GRUB theme selected."; return 0; }
	local install_sh="$base_dir/install.sh"
	local patch_sh="$base_dir/patch_entries.sh"

	[[ -f "$install_sh" ]] || { warn "Missing: $install_sh"; return 0; }
	[[ -f "$patch_sh" ]] || { warn "Missing: $patch_sh"; return 0; }
	chmod +x "$install_sh" "$patch_sh" 2>/dev/null || true

	if ! require_cmd grub-install && ! pacman -Q grub >/dev/null 2>&1 && [[ ! -d /boot/grub ]]; then
		warn "GRUB may not be installed or detected on this system. Proceeding anyway as requested."
	fi

	log "Running GRUB theme installer for: $(basename "$base_dir")"
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
			if [[ -n "$CHOSEN_COLOR_PATH" ]]; then
				update_color_configs "$CHOSEN_COLOR_PATH"
			else
				update_configs
			fi
			deploy_base_configs
			post_steps
			;;
		grub)
			maybe_install_grub_theme "$GRUB_SELECTED_PATH"
			;;
		install|*)
			install_pacman_packages
			install_aur_packages
			if [[ -n "$CHOSEN_COLOR_PATH" ]]; then
				deploy_color_configs "$CHOSEN_COLOR_PATH"
			else
				deploy_configs
			fi
			deploy_base_configs
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