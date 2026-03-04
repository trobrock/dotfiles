#!/usr/bin/env bash

FONT_FAMILY="CaskaydiaCove Nerd Font"

# Get data from shared script
eval "$(bash "$HOME/.config/scripts/openrouter_costs.sh")"

if [[ "$ERROR" == "missing_api_key" ]]; then
  sketchybar --set "$NAME" label="no key"
  exit 0
fi

if [[ "$MODEL_COUNT" -eq 0 ]]; then
  sketchybar --set "$NAME" label="\$0.00"
  exit 0
fi

# Update main bar item
sketchybar --set "$NAME" label="\$${TOTAL_COST}"

# Remove existing popup items
existing_items=$(sketchybar --query bar | jq -r '.items[]' | grep "openrouter_costs.popup" || true)
for item in $existing_items; do
  sketchybar --remove "$item" 2>/dev/null || true
done

# Find the longest model name for alignment
max_model_length=0
for ((i=0; i<MODEL_COUNT; i++)); do
  model_name_var="MODEL_${i}_NAME"
  model_name="${!model_name_var}"
  if [[ ${#model_name} -gt $max_model_length ]]; then
    max_model_length=${#model_name}
  fi
done

# Add popup items for each model — single line per model
for ((i=0; i<MODEL_COUNT; i++)); do
  model_name_var="MODEL_${i}_NAME"
  model_cost_var="MODEL_${i}_COST"
  model_delta_var="MODEL_${i}_DELTA"

  model_name="${!model_name_var}"
  model_cost="${!model_cost_var}"
  model_delta="${!model_delta_var}"

  padding_needed=$((max_model_length - ${#model_name}))
  padding=$(printf "%*s" "$padding_needed" "")

  aligned_label="${model_name}${padding}  \$${model_cost}  (${model_delta})"

  item_name="openrouter_costs.popup.$i"

  sketchybar --add item "$item_name" popup.openrouter_costs.item \
             --set "$item_name" label="$aligned_label" \
                                icon="󰘚" \
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
