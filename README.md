## Lain-themed dotfiles (Hyprland/Wayland)

Personal dotfiles themed after Serial Experiments Lain, with two colorways (blue and white). Includes configs for Hyprland, Waybar, Rofi, SwayNC, Kitty, Cava, btop, and more, plus an optional GRUB theme.

These dotfiles are designed and tested on Arch-based systems (pacman). Other distros can still use the configs manually, but the setup script targets Arch.

---

## Contents

- Hyprland: `hypr/`
- Waybar: `waybar/` (+ `waybar/scripts/`)
- Rofi: `rofi/` (launchers, powermenu, scripts, color themes, images)
- SwayNC: `swaync/`
- Kitty: `kitty/`
- Cava: `cava/`
- btop: `btop/`
- Zsh: `zsh/`
- GRUB theme (optional): `boot_manager/LainGrubTheme-1.0.1/`
- Wallpapers: `hypr/wallpapers/` inside each colorway
 - Dark mode enforcement script: `darkmode.sh` (forces apps/toolkits to prefer dark schemes without copying theme dirs)

Colorways provided:
- `blue/` — dark blue variant
- `white/` — light variant

---

## Quick start (Arch-based)

The setup script installs required packages, backs up existing configs, and deploys the selected theme into `~/.config`.

1) Make the script executable

```sh
chmod +x setup.sh
```

2) Run it (interactive menu will appear)

```sh
./setup.sh
```

You can also skip the menu with a direct action:

- Install packages and deploy configs (recommended on first run):
	```sh
	./setup.sh install
	```
- Update configs only (no package installs):
	```sh
	./setup.sh update
	```
- Install only the GRUB theme:
	```sh
	./setup.sh grub
	```

During install/update you’ll be asked to choose a color theme (blue/white).

---

## What the script does

Safe by default:
- Backs up any existing targets under `~/.config` to `~/.config/.dotfiles_backup_YYYYMMDD-HHMMSS/`
- Deploys configs from the repo (or from your chosen colorway) into `~/.config`
- Makes helper scripts executable (Rofi, Waybar, etc.)
- Optionally sets Zsh as your default shell if installing
- Refreshes font cache when supported

Packages (pacman):
- Installs and/or ensures common Wayland stack and tools:
	- hyprland, hyprpaper, waybar, swaync, rofi, cava, btop, kitty, zsh
	- playerctl, jq, wl-clipboard, grim, slurp, brightnessctl
	- ttf-jetbrains-mono-nerd (font)
	- git, base-devel, flatpak, discover

Packages (AUR via yay):
- Installs: `cbonsai`, `pipes.sh`

Notes:
- The script currently targets Arch-based systems (requires `pacman`).
- If `yay` isn’t present, it will be bootstrapped from AUR.

---

## Manual setup (any distro)

If you don’t want to run the script or you’re not on Arch:

1) Pick a colorway directory (`blue/` or `white/`).
2) Copy the app directories you need into `~/.config` (create it if missing), for example:
	 - `hypr/` → `~/.config/hypr/`
	 - `waybar/` → `~/.config/waybar/`
	 - `rofi/` → `~/.config/rofi/` (ensure `rofi/scripts` and `rofi/applets/bin` are executable)
	 - `swaync/` → `~/.config/swaync/`
	 - `kitty/`, `cava/`, `btop/` similarly
3) Optionally copy a `zshrc` from the repo/theme to `~/.zshrc` and enable zsh.
4) Refresh your font cache if needed: `fc-cache -f`

---

## GRUB theme (optional)

The included theme is in `boot_manager/LainGrubTheme-1.0.1/` and can be installed by running:

```sh
./setup.sh grub
```

This will call the theme’s own `install.sh` and `patch_entries.sh`. You’ll need root privileges and a GRUB setup.

---

## Customization tips

- Wallpapers: edit `hypr/hyprpaper.conf` in your selected colorway to change the wallpaper path.
- Waybar: tweak modules in `waybar/config.jsonc` and styles in `waybar/style.css`. Helper scripts live in `waybar/scripts/`.
- Rofi: set theme in `rofi/config.rasi`; color schemes live in `rofi/colors/`. Launchers and power menus are in `rofi/launchers/` and `rofi/powermenu/`.
- Zsh: adjust `~/.zshrc` after deployment. The config expects zinit (see Credits).
- Fonts: JetBrains Mono Nerd Font is installed by the script on Arch. On other distros, install your preferred Nerd Font and run `fc-cache -f`.

---

## Dark mode enforcement script (`darkmode.sh`)

`darkmode.sh` ONLY enforces dark mode preferences for toolkits/apps. It does **not** deploy any theme directories or overwrite your Hyprland/Waybar/Rofi configs.

What it adjusts (backing up touched files into `~/.config/.darkmode_backup_<timestamp>`):
- GTK3 / GTK4: `gtk-theme-name` + `gtk-application-prefer-dark-theme=1` (default theme: `Adwaita-dark`, override with `--gtk-theme=`)
- QT: writes `~/.config/environment.d/99-darkmode.conf` with dark style hints
- Firefox: adds a small set of dark prefs to each profile's `user.js`
- Chromium / Chrome / Brave: writes flags (`--force-dark-mode`, `--enable-features=WebUIDarkMode`)
- GNOME (if present): tries `gsettings set org.gnome.desktop.interface color-scheme prefer-dark`
- VS Code: untouched by default (enable with `--include-vscode`)

### Usage

Make executable (if needed):
```sh
chmod +x darkmode.sh
```

Apply default dark prefs:
```sh
./darkmode.sh
```

Preview without changing anything:
```sh
./darkmode.sh --dry-run
```

Choose a GTK theme:
```sh
./darkmode.sh --gtk-theme=Catppuccin-Mocha-Standard
```

Include VS Code:
```sh
./darkmode.sh --include-vscode
```

Skip components:
```sh
./darkmode.sh --no-firefox --no-chromium --no-gsettings
```

Force overwrite even if already dark:
```sh
./darkmode.sh --force
```

All options:
```
--gtk-theme=<NAME>    Use specific GTK theme name (default: Adwaita-dark)
--dry-run             Show actions without modifying files
--quiet               Reduce output
--force               Overwrite existing values even if already dark
--no-firefox          Skip Firefox profile modifications
--no-chromium         Skip Chromium/Chrome/Brave flags
--no-gtk              Skip GTK settings
--no-qt               Skip QT environment override
--no-gsettings        Skip gsettings (GNOME) tweak
--include-vscode      ALSO set VS Code UI theme to a dark scheme (disabled by default)
--help                Show usage
```

Backups: Look for the printed backup directory path after a run if you need to restore previous settings.

---

## Troubleshooting

- “pacman not found” or not on Arch
	- Use the Manual setup section, or port the package list to your distro.
- Fonts look wrong or icons missing
	- Ensure a Nerd Font is installed and run `fc-cache -f`. Restart your terminal/Waybar.
- Rofi scripts not executable
	- Make sure `~/.config/rofi/scripts` and `~/.config/rofi/applets/bin` files are `chmod +x`.
- Zsh didn’t become default shell
	- Run `chsh -s "$(command -v zsh)"` and re-login.
- GRUB theme didn’t apply
	- Verify you actually use GRUB, then re-run `./setup.sh grub` with sudo access.

---

## Credits / Upstream

- Zsh plugin manager: https://github.com/zdharma-continuum/zinit
- Rofi menus and assets: https://github.com/adi1090x/rofi
- GRUB theme: https://github.com/uiriansan/LainGrubTheme

All rights belong to their respective authors. This repo assembles and adapts configs for personal use.

---

## License

No explicit license provided for these dotfiles. Refer to upstream projects for their licenses. If you plan to redistribute, please credit the sources above.

---

## Screenshots/preview

Wallpapers live under each colorway at `hypr/wallpapers/`. Swap them in `hyprpaper.conf` to taste. Rofi images and assets are under `rofi/images/`.

---

## Development notes

- Script entrypoint: `setup.sh`
- Backup location format: `~/.config/.dotfiles_backup_YYYYMMDD-HHMMSS`
- Colorway-specific deployment is auto-detected during install/update.
