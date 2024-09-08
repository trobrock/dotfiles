#!/usr/bin/env bash

sketchybar \
           --add item todoist.today right \
           --set      todoist.today icon= \
                                    icon.padding_left=10 \
                                    label="0" \
                                    label.padding_right=10 \
                                    background.color=0x44000000 \
                                    background.corner_radius=3  \
                                    background.height=20 \
                                    update_freq=300 \
                                    script="$PLUGIN_DIR/todoist.sh" \
                                    click_script="open -a Todoist" \

