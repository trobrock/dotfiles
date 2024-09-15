sketchybar \
           --add item github.reviewing right \
           --set      github.reviewing icon= \
                                       icon.color=0xffb4f9f8 \
                                       icon.padding_left=0 \
                                       label="0" \
                                       label.padding_right=$BRACKET_RIGHT_PADDING \
                                       update_freq=300 \
                                       script="$PLUGIN_DIR/github.sh" \
                                       click_script="open 'https://github.com/pulls/review-requested'" \
           --add item github.created right \
           --set      github.created icon= \
                                     icon.color=0xffb4f9f8 \
                                     label="0" \
                                     icon.padding_left=$BRACKET_LEFT_PADDING \
                                     label.padding_right=$BRACKET_SEPERATOR_PADDING \
                                     update_freq=300 \
                                     script="$PLUGIN_DIR/github.sh" \
                                     click_script="open 'https://github.com/pulls'" \
           --add bracket github '/github\./' \
           --set         github ${BACKGROUND_OPTIONS[@]}

