# Bar.qml's contextGroup: a centered ScriptPill showing the upcoming event in
# subtext, hidden unless there actually is one.
#
# NOTE: use `center`, not `e`. Both are accepted, but only `center` actually
# centers on the display -- `e` lands well to the right of center.
sketchybar --add item calendar.today center \
           --set      calendar.today icon="$GLYPH_CALENDAR" \
                                     label="" \
                                     icon.color="$SUBTEXT" \
                                     label.color="$SUBTEXT" \
                                     icon.padding_left=5 \
                                     icon.padding_right=5 \
                                     label.padding_left=0 \
                                     label.padding_right=5 \
                                     drawing=off \
                                     update_freq=300 \
                                     script="$PLUGIN_DIR/calendar.sh"
