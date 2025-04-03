#!/usr/bin/env bash

# Get current time in ISO format
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get agenda from gcalcli
agenda=$(gcalcli --nocolor agenda "$current_time" --tsv --details conference --details location --calendar "Trae Robrock (personal)" --calendar "trobrock@comfort.ly" --calendar "trobrock@robrockproperties.com" --calendar "trae.robrock@huntresslabs.com")

# Process agenda to get the next event
IFS=$'\n' read -d '' -ra lines <<< "$agenda"

# Skip the header line and find the first event
event_found=false
for ((i=1; i<${#lines[@]}; i++)); do
  line="${lines[i]}"
  
  # Split the line by tabs
  IFS=$'\t' read -ra event_data <<< "$line"

  # Check if there's a start time
  if [[ "${event_data[1]}" =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
    start_date="${event_data[0]}"
    start_time="${event_data[1]}"

    if [[ "${event_data[5]}" =~ ^https?:// ]]; then
      conference_url="${event_data[5]}"

      # if position 6 is empty, use position 4 as title
      if [[ -z "${event_data[6]}" ]]; then
        title="${event_data[4]}"
      else
        title="${event_data[6]}"
      fi
    else
      title="${event_data[4]}"
      conference_url=""
    fi

    # If the start time is more than 15 minutes in the past, skip it
    fifteen_minutes_ago=$(date -v -15M +%s)
    start_time_epoch=$(date -j -f "%Y-%m-%d %H:%M" "$start_date $start_time" +%s)
    if [[ $fifteen_minutes_ago -lt $start_time_epoch ]]; then
      event_found=true
      break
    fi
  fi
done

if [[ "$event_found" == true ]]; then
  # Format time
  formatted_time=$(date -j -f "%Y-%m-%d %H:%M" "$start_date $start_time" "+%I:%M %p" 2>/dev/null)
  
  # If date command fails (Linux vs macOS format difference), try alternative
  if [[ -z "$formatted_time" ]]; then
    formatted_time=$(date -d "$start_date $start_time" "+%I:%M %p" 2>/dev/null)
  fi
  
  # Update sketchybar
  sketchybar --set "$NAME" label="$formatted_time - $title" click_script="open $conference_url"
else
  # No event found
  sketchybar --set "$NAME" label="No upcoming events" click_script="echo 'No conference URL available'"
fi

