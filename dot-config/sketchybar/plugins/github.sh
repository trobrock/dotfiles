#!/bin/sh

if [ "$NAME" = "github.created" ]; then
  created=$(gh search prs --state=open --author=@me --archived=false | wc -l | tr -d '[:space:]')
  color=$([ "$created" -gt 0 ] && echo "0xffb4f9f8" || echo "0x44b4f9f8")
  sketchybar --set $NAME label="$created" icon.color="$color"
else
  reviewing=$(gh search prs --state=open --review-requested=@me --archived=false | wc -l | tr -d '[:space:]')
  color=$([ "$reviewing" -gt 0 ] && echo "0xffb4f9f8" || echo "0x44b4f9f8")
  sketchybar --set $NAME label="$reviewing" icon.color="$color"
fi

