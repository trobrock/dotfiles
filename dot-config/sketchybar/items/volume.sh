sketchybar --add event microphone_status_change \
           --add item volume right \
           --set volume script="$PLUGIN_DIR/volume.sh" \
           --subscribe volume volume_change microphone_status_change \
