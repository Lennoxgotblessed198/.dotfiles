#!/usr/bin/env bash
set -euo pipefail

DEV_PATH=""
BEST_TOTAL=-1
for d in /sys/class/drm/card*/device; do
  if [[ -f "$d/mem_info_vram_total" && -f "$d/mem_info_vram_used" ]]; then
    read -r total < "$d/mem_info_vram_total" || total=-1
    [[ -z "$total" ]] && total=-1

    if [[ $total -gt $BEST_TOTAL ]]; then
      BEST_TOTAL=$total
      DEV_PATH="$d"
    fi
  fi
done

if [[ -z "$DEV_PATH" ]]; then
  if command -v amd-smi >/dev/null 2>&1; then
    read -r USED_MB TOTAL_MB < <(amd-smi -q 2>/dev/null | awk '/VRAM Usage/ {in_block=1} in_block && /Total/ {t=$3} in_block && /Used/ {u=$3} END{if(t && u) printf "%s %s", u, t}')
    if [[ -n "${USED_MB:-}" && -n "${TOTAL_MB:-}" ]]; then
      used_gb=$(awk -v m=$USED_MB 'BEGIN{printf "%.1f", m/1024}')
      total_gb=$(awk -v m=$TOTAL_MB 'BEGIN{printf "%.1f", m/1024}')
      printf '{"text":"VRAM %s/%s GB","alt":"amd","class":"amd"}\n' "$used_gb" "$total_gb"
      exit 0
    fi
  fi
  printf '{"text":""}\n'
  exit 0
fi

read -r TOTAL_BYTES < "$DEV_PATH/mem_info_vram_total"
read -r USED_BYTES < "$DEV_PATH/mem_info_vram_used"

if [[ -z "${TOTAL_BYTES:-}" || -z "${USED_BYTES:-}" ]]; then
  printf '{"text":""}\n'
  exit 0
fi

used_gb=$(awk -v b=$USED_BYTES 'BEGIN{printf "%.1f", b/1073741824}')
total_gb=$(awk -v b=$TOTAL_BYTES 'BEGIN{printf "%.1f", b/1073741824}')

printf '{"text":"VRAM %s/%s GB","alt":"amd","class":"amd"}\n' "$used_gb" "$total_gb"
