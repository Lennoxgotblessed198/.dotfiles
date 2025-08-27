#!/usr/bin/env bash
# Single vs double click disambiguation for Waybar modules

set -euo pipefail

STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE_FILE="$STATE_DIR/waybar-arch-click.state"

THRESHOLD_MS=350

now_ms() {
  date +%s%3N
}

run_shutdown() {
  systemctl poweroff
}

run_reboot() {
  systemctl reboot
}

mkdir -p "$STATE_DIR"
now=$(now_ms)

last=0
if [[ -f "$STATE_FILE" ]]; then
  last=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
fi

printf '%s' "$now" > "$STATE_FILE"

if [[ $last -gt 0 ]] && [[ $((now - last)) -lt $THRESHOLD_MS ]]; then
  run_reboot &
  exit 0
fi

( 
  sleep $(awk -v ms=$THRESHOLD_MS 'BEGIN{printf "%.3f", ms/1000}')
  current=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
  if [[ "$current" == "$now" ]]; then
    run_shutdown
  fi
) &

exit 0
