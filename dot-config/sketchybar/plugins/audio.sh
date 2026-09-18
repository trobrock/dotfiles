#!/usr/bin/env bash
# Output volume, mirroring modules/Audio.qml's icon() thresholds:
#
#   muted or 0    GLYPH_VOL_MUTED  (overlay, matching the Quickshell override)
#   >= 67%        GLYPH_VOL_HIGH
#   >= 34%        GLYPH_VOL_MID
#   otherwise     GLYPH_VOL_LOW
#
# The Quickshell module also has a headphones glyph, driven by PipeWire sink
# properties. macOS has no cheap equivalent -- the only reliable source is
# `system_profiler SPAudioDataType`, which takes about a second and is far too
# slow for a bar refresh -- so that state is intentionally omitted.

set -uo pipefail

source "$CONFIG_DIR/theme.sh"

readonly STEP=5

# CoreAudio is the only reliable source for output volume and mute state.
read_state() {
  osascript -e 'set vol to output volume of (get volume settings)' \
            -e 'set m to output muted of (get volume settings)' \
            -e 'return (vol as text) & " " & (m as text)' 2>/dev/null
}

case "$SENDER" in
  mouse.clicked)
    osascript -e 'set volume output muted (not (output muted of (get volume settings)))' \
      >/dev/null 2>&1
    ;;
  mouse.scrolled)
    # SCROLL_DELTA is positive when scrolling up.
    delta=${SCROLL_DELTA:-0}
    current=$(read_state | awk '{print $1}')
    [ -n "$current" ] || exit 0

    if [ "${delta%.*}" -gt 0 ] 2>/dev/null; then
      target=$((current + STEP))
    else
      target=$((current - STEP))
    fi

    [ "$target" -gt 100 ] && target=100
    [ "$target" -lt 0 ] && target=0
    osascript -e "set volume output volume $target" >/dev/null 2>&1
    ;;
esac

state=$(read_state)
volume=$(printf '%s' "$state" | awk '{print $1}')
muted=$(printf '%s' "$state" | awk '{print $2}')

# `output volume` reports "missing value" when no output device is usable.
if [ -z "$volume" ] || ! [[ $volume =~ ^[0-9]+$ ]]; then
  sketchybar --set "$NAME" icon="$GLYPH_VOL_MUTED" icon.color="$OVERLAY"
  exit 0
fi

color=$TEXT
if [ "$muted" = "true" ] || [ "$volume" -eq 0 ]; then
  icon=$GLYPH_VOL_MUTED
  color=$OVERLAY
elif [ "$volume" -ge 67 ]; then
  icon=$GLYPH_VOL_HIGH
elif [ "$volume" -ge 34 ]; then
  icon=$GLYPH_VOL_MID
else
  icon=$GLYPH_VOL_LOW
fi

sketchybar --set "$NAME" icon="$icon" icon.color="$color"
