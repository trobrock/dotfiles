sketchybar --add item calendar.today left \
           --set      calendar.today icon= \
                                    label="" \
                                    icon.padding_left=$BRACKET_LEFT_PADDING \
                                    label.padding_right=$BRACKET_RIGHT_PADDING \
                                    update_freq=300 \
                                    script="$PLUGIN_DIR/calendar.rb" \
           --add bracket calendar '/calendar\./' \
           --set         calendar ${BACKGROUND_OPTIONS[@]}
