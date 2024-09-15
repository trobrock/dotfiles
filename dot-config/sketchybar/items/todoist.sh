sketchybar \
           --add item todoist.today right \
           --set      todoist.today icon= \
                                    icon.color=0xff737aa2 \
                                    label="0" \
                                    icon.padding_left=$BRACKET_LEFT_PADDING \
                                    label.padding_right=$BRACKET_RIGHT_PADDING \
                                    update_freq=300 \
                                    script="$PLUGIN_DIR/todoist.sh" \
                                    click_script="open -a Todoist" \
           --add bracket todoist '/todoist\./' \
           --set         todoist ${BACKGROUND_OPTIONS[@]}

