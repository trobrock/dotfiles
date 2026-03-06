#!/usr/bin/env bash

# Fetches OpenRouter usage/cost data from /api/v1/keys and outputs
# a structured format for consumption by bar plugins.
#
# Shows current month's spend total and per-key breakdown.
# Data is real-time with no lag.
#
# Requires OPENROUTER_MANAGEMENT_KEY in the environment.

if [[ -z "$OPENROUTER_MANAGEMENT_KEY" ]]; then
  echo "TOTAL_COST=0.00"
  echo "KEY_COUNT=0"
  echo "ERROR=missing_api_key"
  exit 0
fi

response=$(curl -sf "https://openrouter.ai/api/v1/keys" \
  -H "Authorization: Bearer $OPENROUTER_MANAGEMENT_KEY" 2>/dev/null)

if [[ $? -ne 0 || -z "$response" ]]; then
  echo "TOTAL_COST=0.00"
  echo "KEY_COUNT=0"
  echo "ERROR=api_error"
  exit 0
fi

# Filter out keys with zero monthly usage and sort by monthly spend descending
keys_data=$(echo "$response" | jq '
  [.data[] | select(.usage_monthly > 0)]
  | sort_by(-.usage_monthly)
')

total_cost=$(echo "$keys_data" | jq '[.[].usage_monthly] | add // 0')
key_count=$(echo "$keys_data" | jq 'length')

total_cost_fmt=$(printf "%.0f" "$total_cost")

echo "TOTAL_COST=$total_cost_fmt"
echo "KEY_COUNT=$key_count"

for i in $(seq 0 $((key_count - 1))); do
  key_name=$(echo "$keys_data" | jq -r ".[$i].name")
  key_cost=$(echo "$keys_data" | jq -r ".[$i].usage_monthly")
  key_cost_fmt=$(printf "%.0f" "$key_cost")

  echo "KEY_${i}_NAME=$key_name"
  echo "KEY_${i}_COST=$key_cost_fmt"
done
