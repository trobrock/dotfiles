# modules/Clock.qml: text only, no icon, 2px padding. The bar passes
# monochrome: true, so it renders in `text` rather than lavender.
sketchybar --add item clock right \
           --set      clock icon.drawing=off \
                            padding_left="$MODULE_SPACING" \
                            label.color="$TEXT" \
                            label.padding_left=2 \
                            label.padding_right=2 \
                            update_freq=10 \
                            script="$PLUGIN_DIR/clock.sh"
