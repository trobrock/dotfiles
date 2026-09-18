# modules/Audio.qml: output volume glyph with horizontalPadding 2. The bar
# passes compact + monochrome, so there is no percentage label and the glyph
# renders in `text` rather than pink.
#
# Clicking toggles mute; scrolling over the item changes volume, matching the
# Quickshell module's wheel handler.
sketchybar --add item audio right \
           --set      audio label.drawing=off \
                            icon.color="$TEXT" \
                            icon.padding_left=2 \
                            icon.padding_right=2 \
                            update_freq=5 \
                            scroll_texts=on \
                            script="$PLUGIN_DIR/audio.sh" \
           --subscribe audio volume_change mouse.clicked mouse.scrolled
