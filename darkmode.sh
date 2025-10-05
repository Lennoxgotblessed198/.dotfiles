#!/usr/bin/env bash

# darkmode.sh
# Purpose: Force applications/toolkits to prefer a dark color scheme WITHOUT
#          copying or altering your dotfile theme directories.
# Scope:   GTK3/GTK4, QT (env overrides), Firefox, Chromium/Chrome/Brave flags,
#          VS Code, Electron/Electron-like apps (via env), optional gsettings.
# Style:   Mirrors logging style used in setup.sh.

set -Eeuo pipefail
shopt -s extglob

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_ROOT="$HOME/.config/.darkmode_backup_$TIMESTAMP"
GTK_THEME="Adwaita-dark"   # Override with --gtk-theme=<NAME>
DRY_RUN=0
QUIET=0
FORCE=0

C_RESET="\033[0m"; C_RED="\033[1;31m"; C_GREEN="\033[1;32m"; C_YELLOW="\033[1;33m"; C_BLUE="\033[1;34m"; C_CYAN="\033[1;36m"
log()  { (( QUIET )) || printf "%b[INFO]%b %s\n" "$C_CYAN"  "$C_RESET" "$*"; }
ok()   { (( QUIET )) || printf "%b[ OK ]%b %s\n" "$C_GREEN" "$C_RESET" "$*"; }
warn() { (( QUIET )) || printf "%b[WARN]%b %s\n" "$C_YELLOW" "$C_RESET" "$*"; }
err()  { printf "%b[FAIL]%b %s\n" "$C_RED"  "$C_RESET" "$*"; }

trap 'err "Error at line $LINENO: $BASH_COMMAND"' ERR

usage() {
  cat <<EOF
Usage: darkmode.sh [options]

Options:
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
  -h|--help             Show this help

Notes:
  Creates backups of modified files under: $BACKUP_ROOT
  Does NOT touch your theme directories or copy dotfiles.
EOF
}

require_cmd() { command -v "$1" >/dev/null 2>&1; }

backup_file() {
  local f="$1"
  [[ -e "$f" || -L "$f" ]] || return 0
  mkdir -p "$BACKUP_ROOT"
  local rel
  rel="${f#$HOME/}" # relative-ish
  local dest="$BACKUP_ROOT/${rel//\//__}"
  log "Backup: $f -> $dest"
  (( DRY_RUN )) || cp -a "$f" "$dest"
}

ensure_line_kv_ini() {
  # ensure_line_kv_ini <file> <section> <key> <value>
  local file="$1" section="$2" key="$3" value="$4"
  local tmp="${file}.tmp.$$"
  local had_section=0
  local replaced=0
  [[ -f "$file" ]] || echo "[$section]" > "$file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\[$section\]$ ]]; then
      had_section=1
      echo "$line" >>"$tmp"
      continue
    fi
    if (( had_section )) && [[ "$line" =~ ^\[.+\]$ ]]; then
      # New section encountered and we haven't written our key
      if (( replaced == 0 )); then
        echo "$key=$value" >>"$tmp"
        replaced=1
      fi
      had_section=0
    fi
    if (( had_section )) && [[ "$line" =~ ^$key= ]]; then
      if (( FORCE )) || [[ ! "$line" =~ =$value$ ]]; then
        echo "$key=$value" >>"$tmp"; replaced=1; continue
      else
        # leave as is
        replaced=1
      fi
    fi
    echo "$line" >>"$tmp"
  done < "$file"
  if (( had_section )) && (( replaced == 0 )); then
    echo "$key=$value" >>"$tmp"
  fi
  (( DRY_RUN )) || mv "$tmp" "$file"
  (( DRY_RUN )) && rm -f "$tmp" || true
}

apply_gtk() {
  local gtk_files=( "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini" )
  for f in "${gtk_files[@]}"; do
    local dir="$(dirname "$f")"; mkdir -p "$dir"
    [[ -f "$f" ]] && backup_file "$f"
    log "Setting GTK theme=$GTK_THEME in $(basename "$dir")"
    (( DRY_RUN )) || touch "$f"
    ensure_line_kv_ini "$f" Settings gtk-theme-name "$GTK_THEME"
    ensure_line_kv_ini "$f" Settings gtk-application-prefer-dark-theme 1
    ok "GTK dark preference applied: $f"
  done
}

apply_qt() {
  local envdir="$HOME/.config/environment.d"; local f="$envdir/99-darkmode.conf"
  mkdir -p "$envdir"
  [[ -f "$f" ]] && backup_file "$f"
  log "Writing QT/GTK environment overrides: $f"
  (( DRY_RUN )) || cat > "$f" <<EOF
# Added by darkmode.sh
QT_STYLE_OVERRIDE=${GTK_THEME%-dark}-Dark
GTK_THEME=${GTK_THEME/:/-}
XDG_CURRENT_DESKTOP=
EOF
  ok "QT environment override set (new sessions required)"
}

apply_firefox() {
  local base="$HOME/.mozilla/firefox"
  [[ -d "$base" ]] || { warn "Firefox not found; skipping"; return 0; }
  local profiles=()
  while IFS= read -r -d '' d; do profiles+=("$d"); done < <(find "$base" -maxdepth 1 -type d -name "*.default*" -print0 2>/dev/null)
  (( ${#profiles[@]} )) || { warn "No Firefox profiles; skipping"; return 0; }
  for p in "${profiles[@]}"; do
    local userjs="$p/user.js"; [[ -f "$userjs" ]] && backup_file "$userjs"
    log "Enforcing dark prefs in profile: $(basename "$p")"
    (( DRY_RUN )) && continue
    # Remove existing lines for these prefs to avoid duplicates
    local tmp="${userjs}.tmp"; [[ -f "$userjs" ]] && grep -v -E 'layout.css.prefers-color-scheme.content-override|ui.systemUsesDarkTheme|browser.in-content.dark-mode|devtools.theme|extensions.activeThemeID' "$userjs" > "$tmp" || true
    [[ -f "$tmp" ]] && mv "$tmp" "$userjs" || true
    {
      echo '// Added by darkmode.sh'
      echo 'user_pref("layout.css.prefers-color-scheme.content-override", 2);'   # 2 = force dark
      echo 'user_pref("ui.systemUsesDarkTheme", 1);'
      echo 'user_pref("browser.in-content.dark-mode", true);'
      echo 'user_pref("devtools.theme", "dark");'
      echo 'user_pref("extensions.activeThemeID", "firefox-compact-dark@mozilla.org");'
    } >> "$userjs"
    ok "Firefox profile updated (restart Firefox)"
  done
}

apply_chromium() {
  local targets=( "$HOME/.config/chromium-flags.conf" "$HOME/.config/chrome-flags.conf" )
  for t in "${targets[@]}"; do
    [[ -f "$t" ]] && backup_file "$t"
    log "Writing dark flags: $t"
    (( DRY_RUN )) || cat > "$t" <<'EOF'
--force-dark-mode
--enable-features=WebUIDarkMode
EOF
    ok "Chromium flags written"
  done
  # Brave variant
  if [[ -d "$HOME/.config/BraveSoftware/Brave-Browser" ]]; then
    local f="$HOME/.config/brave-flags.conf"
    [[ -f "$f" ]] && backup_file "$f"
    log "Writing dark flags: brave-flags.conf"
    (( DRY_RUN )) || cat > "$f" <<'EOF'
--force-dark-mode
--enable-features=WebUIDarkMode
EOF
    ok "Brave flags written"
  fi
}

apply_vscode() {
  local dir="$HOME/.config/Code/User"; local f="$dir/settings.json"; mkdir -p "$dir"
  [[ -f "$f" ]] && backup_file "$f"
  log "Setting VS Code dark theme preference"
  (( DRY_RUN )) && return 0
  if require_cmd jq && [[ -f "$f" ]]; then
    local tmp="${f}.tmp"
    jq '."workbench.colorTheme"="Default Dark+"' "$f" 2>/dev/null > "$tmp" || echo '{"workbench.colorTheme": "Default Dark+"}' > "$tmp"
    mv "$tmp" "$f"
  else
    echo '{"workbench.colorTheme": "Default Dark+"}' > "$f"
  fi
  ok "VS Code preference updated (restart if running)"
}

apply_gsettings() {
  if require_cmd gsettings; then
    log "Attempting to set GNOME/portal color-scheme preference"
    if gsettings writable org.gnome.desktop.interface color-scheme >/dev/null 2>&1; then
      (( DRY_RUN )) || gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' || warn "gsettings set failed"
      ok "gsettings color-scheme=prefer-dark applied"
    else
      warn "color-scheme key not writable or unsupported"
    fi
  else
    log "gsettings not found; skipping"
  fi
}

# Defaults: all enabled EXCEPT VS Code (user requested no change there)
DO_FIREFOX=1; DO_CHROMIUM=1; DO_VSCODE=0; DO_GTK=1; DO_QT=1; DO_GSETTINGS=1

parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --gtk-theme=*) GTK_THEME="${arg#*=}" ;;
      --dry-run) DRY_RUN=1 ;;
      --quiet) QUIET=1 ;;
      --force) FORCE=1 ;;
      --no-firefox) DO_FIREFOX=0 ;;
      --no-chromium) DO_CHROMIUM=0 ;;
  --include-vscode) DO_VSCODE=1 ;;
      --no-gtk) DO_GTK=0 ;;
      --no-qt) DO_QT=0 ;;
      --no-gsettings) DO_GSETTINGS=0 ;;
      -h|--help) usage; exit 0 ;;
      *) warn "Unknown option: $arg" ;;
    esac
  done
}

summary() {
  printf "\n"
  (( QUIET )) || printf "%b[INFO]%b Summary:\n" "$C_CYAN" "$C_RESET"
  (( DO_GTK )) && log " GTK: theme=$GTK_THEME"
  (( DO_QT )) && log " QT: env override"
  (( DO_FIREFOX )) && log " Firefox: user.js prefs"
  (( DO_CHROMIUM )) && log " Chromium/Chrome/Brave: flags"
  (( DO_VSCODE )) && log " VS Code: colorTheme=Default Dark+ (explicitly enabled)"
  (( DO_GSETTINGS )) && log " gsettings: color-scheme prefer-dark"
  (( DRY_RUN )) && warn "DRY RUN: no files modified" || true
  [[ -d "$BACKUP_ROOT" ]] && warn "Backups stored in: $BACKUP_ROOT" || true
}

main() {
  parse_args "$@"
  log "Enforcing application/toolkit dark mode preferences"
  (( DO_GTK )) && apply_gtk || log "GTK skipped"
  (( DO_QT )) && apply_qt || log "QT skipped"
  (( DO_FIREFOX )) && apply_firefox || log "Firefox skipped"
  (( DO_CHROMIUM )) && apply_chromium || log "Chromium skipped"
  (( DO_VSCODE )) && apply_vscode || log "VS Code skipped"
  (( DO_GSETTINGS )) && apply_gsettings || log "gsettings skipped"
  ok "Dark mode preference pass complete"
  summary
}

main "$@"
