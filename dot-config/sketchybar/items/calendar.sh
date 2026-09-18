# Bar.qml's contextGroup: a ScriptPill showing the upcoming event in subtext,
# hidden unless there actually is one.
#
# Placed on the left instead of centered. `center` would put the label under the
# MacBook's camera notch, and the left side simply has more room for a long
# event title than the gap between the notch and the status cluster.
sketchybar --add item calendar.today left \
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
