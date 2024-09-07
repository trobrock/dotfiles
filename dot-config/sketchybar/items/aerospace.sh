sketchybar --add event aerospace_workspace_change \
           --add event aerospace_window_moved

space_commands=()
for sid in $(aerospace list-workspaces --all); do
  space_commands+=(--add item space.$sid left \
             --set space.$sid \
             label="$sid" \
             icon.drawing=off \
             click_script="aerospace workspace $sid")
done
sketchybar "${space_commands[@]}"

sketchybar --add bracket aerospace '/space\./' \
           --subscribe   aerospace aerospace_workspace_change aerospace_window_moved \
           --set         aerospace background.color=0x77000000 \
                                   background.corner_radius=3  \
                                   background.padding_right=40 \
                                   background.height=20 \
                                   script="$PLUGIN_DIR/aerospace.sh"

