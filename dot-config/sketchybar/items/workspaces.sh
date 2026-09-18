sketchybar --add event aerospace_workspace_change \
           --add event aerospace_window_moved

# sketchybar can be started (by its launchd agent) before the aerospace CLI
# is ready. If we query too early, list-workspaces returns nothing and no
# space items get created. Retry briefly until aerospace responds.
workspaces=""
for _ in $(seq 1 30); do
  workspaces=$(aerospace list-workspaces --all 2>/dev/null)
  [ -n "$workspaces" ] && break
  sleep 1
done

# modules/Workspaces.qml in minimal mode: no pill background, just a colored
# label with a 14x2 rounded indicator pinned to the bottom of the button.
#
# sketchybar's background always spans the item's content width and
# background.padding_* does not inset it, so the 14px indicator is produced by
# sizing the content itself: a digit is ~8px at 14px, plus 3px label padding
# either side. The 5px item padding then sits OUTSIDE the background, giving a
# ~24px pitch that matches Quickshell's 24px button + 1px spacing.
space_commands=()
for sid in $workspaces; do
  space_commands+=(--add item "space.$sid" left \
             --set "space.$sid" \
             label="$sid" \
             icon.drawing=off \
             padding_left=5 \
             padding_right=5 \
             label.padding_left=3 \
             label.padding_right=3 \
             label.color="$OVERLAY" \
             background.drawing=on \
             background.color="$TRANSPARENT" \
             background.height="$INDICATOR_HEIGHT" \
             background.corner_radius="$INDICATOR_HEIGHT" \
             background.y_offset="$INDICATOR_Y_OFFSET" \
             click_script="aerospace workspace $sid")
done
sketchybar "${space_commands[@]}"

# The bracket is only a grouping handle for the plugin's query -- it draws
# nothing, matching Quickshell's flat BarGroup.
# AeroSpace only emits events for workspace switches and explicit window moves,
# so front_app_switched is added to catch windows merely opening or closing --
# otherwise the overflow workspaces stay visible after their last window goes.
sketchybar --add bracket aerospace '/space\./' \
           --subscribe   aerospace aerospace_workspace_change \
                                   aerospace_window_moved \
                                   front_app_switched \
           --set         aerospace background.drawing=off \
                                   script="$PLUGIN_DIR/workspaces.sh"
