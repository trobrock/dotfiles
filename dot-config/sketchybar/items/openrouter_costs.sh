sketchybar --add item openrouter_costs.item right \
           --set      openrouter_costs.item icon=󰘚 \
                                            label="\$0.00" \
                                            icon.padding_left=$BRACKET_LEFT_PADDING \
                                            label.padding_right=$BRACKET_RIGHT_PADDING \
                                            update_freq=300 \
                                            script="$PLUGIN_DIR/openrouter_costs.sh" \
                                            click_script="sketchybar --set openrouter_costs.item popup.drawing=toggle" \
           --add bracket openrouter_costs '/openrouter_costs\./' \
           --set         openrouter_costs ${BACKGROUND_OPTIONS[@]}
