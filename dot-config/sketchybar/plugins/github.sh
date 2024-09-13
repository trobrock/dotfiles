#!/bin/sh

if [ "$NAME" = "github.created" ]; then
  created=$(gh search prs --state=open --author=@me | wc -l | tr -d '[:space:]')
  sketchybar --set $NAME label="$created"
else
  reviewing=$(gh search prs --state=open --review-requested=@me | wc -l | tr -d '[:space:]')
  sketchybar --set $NAME label="$reviewing"
fi

