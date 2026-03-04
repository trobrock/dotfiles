#!/usr/bin/env bash

# Fetches OpenRouter usage/cost data for the past 14 days and outputs
# a structured format for consumption by bar plugins.
# Current period: days 0-6, Previous period: days 7-13
#
# Past days are cached individually since their data won't change.
# Only today's data is fetched fresh each run.
#
# Requires OPENROUTER_MANAGEMENT_KEY in the environment.
# API: GET https://openrouter.ai/api/v1/activity?date=YYYY-MM-DD

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/openrouter-costs"
mkdir -p "$CACHE_DIR"

if [[ -z "$OPENROUTER_MANAGEMENT_KEY" ]]; then
  echo "TOTAL_COST=0.00"
  echo "MODEL_COUNT=0"
  echo "ERROR=missing_api_key"
  exit 0
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
  today=$(date +"%Y-%m-%d")
else
  today=$(date +"%Y-%m-%d")
fi

fetch_day() {
  local day="$1"
  local cache_file="$CACHE_DIR/$day.json"

  # Use cache for past days, always fetch today fresh
  if [[ "$day" != "$today" && -f "$cache_file" ]]; then
    cat "$cache_file"
    return
  fi

  local response
  response=$(curl -sf "https://openrouter.ai/api/v1/activity?date=$day" \
    -H "Authorization: Bearer $OPENROUTER_MANAGEMENT_KEY" 2>/dev/null)

  if [[ $? -eq 0 && -n "$response" ]]; then
    local day_data
    day_data=$(echo "$response" | jq -r '.data // []')

    # Cache past days permanently
    if [[ "$day" != "$today" ]]; then
      echo "$day_data" > "$cache_file"
    fi

    echo "$day_data"
  else
    echo "[]"
  fi
}

# Clean up cache files older than 15 days
find "$CACHE_DIR" -name "*.json" -mtime +15 -delete 2>/dev/null

# Collect activity data for each of the past 14 days
current_data="[]"
previous_data="[]"
for i in $(seq 0 13); do
  if [[ "$OSTYPE" == "darwin"* ]]; then
    day=$(date -v-${i}d +"%Y-%m-%d")
  else
    day=$(date -d "$i days ago" +"%Y-%m-%d")
  fi

  day_data=$(fetch_day "$day")

  if [[ $i -lt 7 ]]; then
    current_data=$(echo "$current_data" "$day_data" | jq -s '.[0] + .[1]')
  else
    previous_data=$(echo "$previous_data" "$day_data" | jq -s '.[0] + .[1]')
  fi
done

# Aggregate a dataset by model
aggregate() {
  echo "$1" | jq '
    group_by(.model)
    | map({
        model: .[0].model,
        cost: (map(.usage) | add // 0)
      })
    | sort_by(-.cost)
  '
}

current_agg=$(aggregate "$current_data")
previous_agg=$(aggregate "$previous_data")

total_cost=$(echo "$current_agg" | jq '[.[].cost] | add // 0')
prev_total_cost=$(echo "$previous_agg" | jq '[.[].cost] | add // 0')
model_count=$(echo "$current_agg" | jq 'length')

total_cost_fmt=$(printf "%.0f" "$total_cost")
total_delta=$(echo "$total_cost $prev_total_cost" | awk '{d = $1 - $2; if (d >= 0) printf "+%.0f", d; else printf "%.0f", d}')

echo "TOTAL_COST=$total_cost_fmt"
echo "TOTAL_DELTA=$total_delta"
echo "MODEL_COUNT=$model_count"

for i in $(seq 0 $((model_count - 1))); do
  model=$(echo "$current_agg" | jq -r ".[$i].model")
  cost=$(echo "$current_agg" | jq -r ".[$i].cost")

  # Look up previous period cost for this model
  prev_cost=$(echo "$previous_agg" | jq -r --arg m "$model" '[.[] | select(.model == $m) | .cost] | add // 0')

  cost_fmt=$(printf "%.0f" "$cost")
  delta=$(echo "$cost $prev_cost" | awk '{d = $1 - $2; if (d >= 0) printf "+%.0f", d; else printf "%.0f", d}')

  echo "MODEL_${i}_NAME=$model"
  echo "MODEL_${i}_COST=$cost_fmt"
  echo "MODEL_${i}_DELTA=$delta"
done
