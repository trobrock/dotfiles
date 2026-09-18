# macOS-only extra (no Linux counterpart): time tracked today. Restyled flat
# with subtext to sit quietly next to the workspaces.
sketchybar --add item project_time.today left \
           --set      project_time.today icon="$GLYPH_CLOCK" \
                                         label="0h0m" \
                                         icon.color="$SUBTEXT" \
                                         label.color="$SUBTEXT" \
                                         icon.padding_left=5 \
                                         icon.padding_right=5 \
                                         label.padding_left=0 \
                                         label.padding_right=5 \
                                         update_freq=300 \
                                         script="$PLUGIN_DIR/project_time.sh" \
                                         click_script="sketchybar --set project_time.today popup.drawing=toggle"
