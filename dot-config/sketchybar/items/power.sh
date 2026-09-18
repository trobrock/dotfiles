# PowerMenu.qml equivalent. The item is a zero-width anchor at the right edge
# with nothing drawn; it exists only so the popup has a position.
#
# alt-shift-esc triggers power_menu_toggle rather than setting popup.drawing
# directly, because the menu contents have to be rendered before the popup is
# shown.
sketchybar --add event power_menu_toggle \
           --add item  power right \
           --set       power width=0 \
                             icon.drawing=off \
                             label.drawing=off \
                             background.drawing=off \
                             popup.align=right \
                             script="$PLUGIN_DIR/power.sh" \
           --subscribe power power_menu_toggle
