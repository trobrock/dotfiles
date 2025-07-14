#!/usr/bin/env bash

weather="$(curl -s 'https://wttr.in/?format=%c%t')"
tooltip="$(curl -s 'https://wttr.in/?1TdF')"

echo "$weather" | jq -R -s --arg tooltip "$tooltip" --arg weather "$weather" \
    '{
        "text": $weather,
        "tooltip": $tooltip
    }' | jq -c .
