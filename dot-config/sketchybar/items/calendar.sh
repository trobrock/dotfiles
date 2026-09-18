# Bar.qml's contextGroup: a ScriptPill showing the upcoming event in subtext,
# hidden unless there actually is one.
#
# NOTE: this uses `e` (right of center), NOT `center`. True center would put the
# label underneath the MacBook's camera notch, where it is partly hidden. The
# Linux bar can center it because there is no notch to avoid.
sketchybar --add item calendar.today e \
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
