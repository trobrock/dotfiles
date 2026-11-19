# Todoist due-today counter and task popup. Data comes from the shared
# ~/.config/scripts/todoist-bar helper, which keeps the API token outside this
# public repository.
sketchybar --add item todoist right \
           --set      todoist icon="$GLYPH_TODOIST" \
                                 icon.color="$SUBTEXT" \
                                 label="" \
                                 label.color="$TEXT" \
                                 icon.padding_left=3 \
                                 icon.padding_right=1 \
                                 label.padding_left=1 \
                                 label.padding_right=4 \
                                 update_freq=300 \
                                 click_script="$PLUGIN_DIR/todoist.sh toggle" \
                                 script="$PLUGIN_DIR/todoist.sh" \
           --subscribe todoist system_woke
