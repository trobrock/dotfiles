#!/usr/bin/env bash

# Get data from shared script
eval "$(bash "$HOME/.config/scripts/openrouter_costs.sh")"

if [[ "$ERROR" == "missing_api_key" ]]; then
  echo '{"text": "no key", "tooltip": "OPENROUTER_MANAGEMENT_KEY not set", "class": "openrouter-costs"}'
  exit 0
fi

if [[ "$MODEL_COUNT" -eq 0 ]]; then
  echo '{"text": "$0.00", "tooltip": "No OpenRouter usage in the past 7 days", "class": "openrouter-costs"}'
  exit 0
fi

tooltip="OpenRouter — 7 day costs (${TOTAL_DELTA} vs prev)\\n"

# Find the longest model name for alignment
max_model_length=0
for ((i=0; i<MODEL_COUNT; i++)); do
  model_name_var="MODEL_${i}_NAME"
  model_name="${!model_name_var}"
  if [[ ${#model_name} -gt $max_model_length ]]; then
    max_model_length=${#model_name}
  fi
done

# Add each model with aligned costs and delta
for ((i=0; i<MODEL_COUNT; i++)); do
  model_name_var="MODEL_${i}_NAME"
  model_cost_var="MODEL_${i}_COST"
  model_delta_var="MODEL_${i}_DELTA"

  model_name="${!model_name_var}"
  model_cost="${!model_cost_var}"
  model_delta="${!model_delta_var}"

  padding_needed=$((max_model_length - ${#model_name}))
  padding=$(printf "%*s" "$padding_needed" "")

  tooltip+="\\n󰘚 ${model_name}${padding}  \$${model_cost}  (${model_delta})"
done

# Output JSON format for waybar
echo "{\"text\": \"\$${TOTAL_COST}\", \"tooltip\": \"$tooltip\", \"class\": \"openrouter-costs\"}"
