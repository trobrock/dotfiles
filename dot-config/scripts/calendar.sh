#!/usr/bin/env bash

source "$HOME/.config/scripts/utils.sh"

# Get current time in ISO format
current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Get agenda from gcalcli
agenda=$(gcalcli --nocolor agenda "$current_time" --tsv --details conference --details location --details description --nodeclined --calendar "Trae Robrock (personal)" --calendar "trobrock@comfort.ly" --calendar "trobrock@robrockproperties.com" --calendar "trae.robrock@huntresslabs.com")

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

    if [[ "${event_data[4]}" == "video" ]]; then
      title="${event_data[6]}"
    else
      title="${event_data[4]}"
    fi

    if [[ "${event_data[5]}" =~ ^https?:// ]]; then
      conference_url="${event_data[5]}"
    else
      if [[ "${event_data[6]}" =~ https?://.*\.zoom\.us ]]; then # description contains zoom link
        conference_url=$(echo "${event_data[6]}" | sed -En 's/.*(https:\/\/([a-z0-9]*\.)?zoom\.us\/[\/a-zA-Z0-9]+).*/\1/p')
      else
        conference_url=""
      fi
    fi

    # If the start time is more than 15 minutes in the past, skip it
    fifteen_minutes_ago=$(date_from_string "15 minutes ago")
    start_time_epoch=$(date_from_string "$start_date $start_time")
    if [[ $fifteen_minutes_ago -lt $start_time_epoch ]] && [[ "$title" != "busy" ]]; then
      event_found=true
      break
    fi
  fi
done

if [[ "$event_found" == true ]]; then
  formatted_time=$(date_from_string "$start_date $start_time" "+%I:%M %p")
  title=$(truncate "$title" 25)

  echo '{"title":"'$formatted_time' - '$title'", "conference_url":"'$conference_url'"}'
else
  echo '{"title":"No upcoming events", "conference_url":""}'
fi

