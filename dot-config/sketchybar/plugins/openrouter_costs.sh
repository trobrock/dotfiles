#!/usr/bin/env bash

# Ensure standard file descriptors are valid — sketchybar may close them,
# which causes Python (gcalcli) to crash during stream initialization.
[[ -t 0 ]] || exec 0</dev/null
[[ -t 1 ]] || exec 1>/dev/null
[[ -t 2 ]] || exec 2>/dev/null

FONT_FAMILY="CaskaydiaCove Nerd Font"

# Get data from shared script
eval "$(bash "$HOME/.config/scripts/openrouter_costs.sh")"

if [[ "$ERROR" == "missing_api_key" ]]; then
  sketchybar --set "$NAME" label="no key"
  exit 0
fi

if [[ "$KEY_COUNT" -eq 0 ]]; then
  sketchybar --set "$NAME" label="\$0"
  exit 0
fi

# Update main bar item
sketchybar --set "$NAME" label="\$${TOTAL_COST}"

# Remove existing popup items
existing_items=$(sketchybar --query bar | jq -r '.items[]' | grep "openrouter_costs.popup" || true)
for item in $existing_items; do
  sketchybar --remove "$item" 2>/dev/null || true
done

# Find the longest key name for alignment
max_name_length=0
for ((i=0; i<KEY_COUNT; i++)); do
  key_name_var="KEY_${i}_NAME"
  key_name="${!key_name_var}"
  if [[ ${#key_name} -gt $max_name_length ]]; then
    max_name_length=${#key_name}
  fi
done

# Add popup items for each key
for ((i=0; i<KEY_COUNT; i++)); do
  key_name_var="KEY_${i}_NAME"
  key_cost_var="KEY_${i}_COST"

  key_name="${!key_name_var}"
  key_cost="${!key_cost_var}"

  padding_needed=$((max_name_length - ${#key_name}))
  padding=$(printf "%*s" "$padding_needed" "")

  aligned_label="${key_name}${padding}  \$${key_cost}"

  item_name="openrouter_costs.popup.$i"

  sketchybar --add item "$item_name" popup.openrouter_costs.item \
             --set "$item_name" label="$aligned_label" \
                                icon="󰌌" \
                                icon.color=0xffffffff \
                                label.color=0xffffffff \
                                label.font="$FONT_FAMILY:Mono:13.0" \
                                background.drawing=on \
                                background.color=0xdd24273a \
                                background.corner_radius=6 \
                                background.height=28 \
                                background.border_width=1 \
                                background.border_color=0x44ffffff \
                                label.padding_left=12 \
                                label.padding_right=12 \
                                icon.padding_left=8 \
                                icon.padding_right=4
done
