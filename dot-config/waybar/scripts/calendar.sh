#!/usr/bin/env bash

data="$(~/.config/scripts/calendar.sh)"
title=$(echo "$data" | jq -r '.title')

echo '{"text":"'$title'"}'
