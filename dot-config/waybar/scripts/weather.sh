#!/usr/bin/env bash

location="$(curl -s ipinfo.io | jq -r '.loc')"
weather=$(curl -s "https://wttr.in/$location?u&format=%c%t")
tooltip=$(curl -s "https://wttr.in/$location?1TdFu")

echo "$weather" | jq -R -s --arg tooltip "$tooltip" --arg weather "$weather" \
    '{
        "text": $weather,
        "tooltip": $tooltip
    }' | jq -c .
