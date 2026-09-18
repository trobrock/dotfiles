# macOS-only extra (no Linux counterpart): current focus block. Restyled flat
# with mauve text to match the Quickshell design language.
sketchybar --add item focus.today left \
           --set      focus.today icon="$GLYPH_FOCUS" \
                                  label="" \
                                  icon.color="$MAUVE" \
                                  label.color="$MAUVE" \
                                  icon.padding_left=5 \
                                  icon.padding_right=5 \
                                  label.padding_left=0 \
                                  label.padding_right=5 \
                                  update_freq=60 \
                                  script="$PLUGIN_DIR/focus.sh"
