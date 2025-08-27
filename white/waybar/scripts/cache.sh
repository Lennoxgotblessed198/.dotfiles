#!/usr/bin/env bash

set -Eeuo pipefail
shopt -s nullglob

human() {
	local bytes=$1
	local -a units=(B KiB MiB GiB TiB PiB)
	local i=0
	while (( bytes >= 1024 && i < ${#units[@]}-1 )); do
		bytes=$((bytes/1024))
		((i++))
	done
	printf "%d%s" "$bytes" "${units[$i]}"
}

# Collect cache directories (user storage cache, not RAM)
XDG_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
declare -a CACHE_DIRS
CACHE_DIRS+=("$XDG_CACHE_DIR")

# Flatpak app caches under ~/.var/app/*/cache
for d in "$HOME/.var/app"/*/cache; do
	[[ -d "$d" ]] && CACHE_DIRS+=("$d")
done

# Sum sizes in bytes
total_cache_bytes=0
tooltip_lines=()
for d in "${CACHE_DIRS[@]}"; do
	if [[ -d "$d" ]]; then
		sz=$(du -sb "$d" 2>/dev/null | awk '{print $1}') || sz=0
		total_cache_bytes=$(( total_cache_bytes + sz ))
		tooltip_lines+=("$d: $(human "$sz")")
	fi
done

# Filesystem size for $HOME (bytes)
home_fs_total=$(df -B1 --output=size "$HOME" 2>/dev/null | tail -1 | tr -d ' ')
[[ -z "$home_fs_total" ]] && home_fs_total=0

percentage=0
if (( home_fs_total > 0 )); then
	percentage=$(( total_cache_bytes * 100 / home_fs_total ))
fi

text=$(human "$total_cache_bytes")

# Build tooltip
tooltip="Home storage cache: $text"
if (( ${#tooltip_lines[@]} > 0 )); then
	tooltip+=$'\n'"$(printf '%s\n' "${tooltip_lines[@]}")"
fi

printf '{"text":"%s","percentage":%d,"tooltip":"%s"}\n' "$text" "$percentage" "$tooltip"