#!/usr/bin/env bash
set -euo pipefail

status=$(playerctl --player=spotify status 2>/dev/null || true)

if [[ "$status" == "Playing" || "$status" == "Paused" ]]; then
    artist=$(playerctl --player=spotify metadata artist 2>/dev/null || echo "")
    title=$(playerctl --player=spotify metadata title 2>/dev/null || echo "")
    if command -v jq >/dev/null 2>&1; then
        jq -nc --arg text "${artist:+$artist - }$title" --arg class "$status" '{text:$text, class:$class}'
    else
        text="${artist:+$artist - }$title"
        text=${text//\\/\\\\}
        text=${text//\"/\\\"}
        text=${text//$'\n'/ }
        text=${text//$'\r'/ }
        text=${text//$'\t'/ }
        printf '{"text":"%s","class":"%s"}\n' "$text" "$status"
    fi
else
    printf '{"text":""}\n'
fi
