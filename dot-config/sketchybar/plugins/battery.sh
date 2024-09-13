#!/bin/sh

PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
CHARGING="$(pmset -g batt | grep 'AC Power')"

if [ "$PERCENTAGE" = "" ]; then
  exit 0
fi

case "${PERCENTAGE}" in
  9[0-9]|100)
    ICON=""
    COLOR=0xff4fd6be
  ;;
  [6-8][0-9])
    ICON=""
    COLOR=0xffffc777
  ;;
  [3-5][0-9])
    ICON=""
    COLOR=0xffff9e64
  ;;
  [1-2][0-9])
    ICON=""
    COLOR=0xffc53b53
  ;;
  *)
    ICON=""
    COLOR=0xff737aa2
esac

if [[ "$CHARGING" != "" ]]; then
  ICON=""
  COLOR=0xffffc777
fi

# The item invoking this script (name $NAME) will get its icon and label
# updated with the current battery status
sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="$PERCENTAGE%"