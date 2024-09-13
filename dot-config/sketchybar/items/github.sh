sketchybar \
           --add item github.reviewing right \
           --set      github.reviewing icon= \
                                       icon.color=0xffb4f9f8 \
                                       icon.padding_left=0 \
                                       label="0" \
                                       label.padding_right=5 \
                                       update_freq=300 \
                                       script="$PLUGIN_DIR/github.sh" \
                                       click_script="open 'https://github.com/pulls/review-requested'" \
           --add item github.created right \
           --set      github.created icon= \
                                     icon.color=0xffb4f9f8 \
                                     icon.padding_left=5 \
                                     label="0" \
                                     label.padding_right=5 \
                                     update_freq=300 \
                                     script="$PLUGIN_DIR/github.sh" \
                                     click_script="open 'https://github.com/pulls'" \
           --add bracket github '/github\./' \
           --set         github background.color=0x44000000 \
                                background.corner_radius=3  \
                                background.height=20

