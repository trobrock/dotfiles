#!/usr/bin/env bash

data="$(~/.config/scripts/calendar.sh)"
title=$(echo "$data" | jq -r '.title')

# strip < and > from the title
title=$(echo "$title" | sed 's/[<>]//g')

# change & to &amp;
title=$(echo "$title" | sed 's/&/\&amp;/g')

echo '{"text":"'$title'"}'
