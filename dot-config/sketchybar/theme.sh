#!/usr/bin/env bash
# Catppuccin Mocha design tokens, mirroring dot-config/quickshell/Theme.qml.
#
# Keep this in sync with Theme.qml so the macOS bar and the Linux Quickshell bar
# stay visually identical. Colors are sketchybar's 0xAARRGGBB format.

# sketchybar exports only CONFIG_DIR to scripts -- PLUGIN_DIR and SCRIPT_DIR are
# plain shell variables in sketchybarrc and are empty inside plugins. Plugins
# that build click_scripts need them at runtime, so re-derive them here without
# clobbering the values sketchybarrc already set.
export CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/sketchybar}"
export PLUGIN_DIR="${PLUGIN_DIR:-$CONFIG_DIR/plugins}"
export SCRIPT_DIR="${SCRIPT_DIR:-$CONFIG_DIR/scripts}"
export ITEM_DIR="${ITEM_DIR:-$CONFIG_DIR/items}"

export FONT_FAMILY="CaskaydiaCove Nerd Font"
export FONT_SIZE=14
export BAR_HEIGHT=32
export RADIUS=10

# Theme.qml: base #1e1e2e. Bar.qml fills the panel with base at 43% alpha and
# draws a 1px bottom hairline of surface1 at 70% alpha.
export BASE=0xff1e1e2e
export BAR_COLOR=0x6e1e2e2e
export HAIRLINE=0xb345475a

export SURFACE=0x99313244
export SURFACE_SOLID=0xff313244
export SURFACE1=0xff45475a
export OVERLAY=0xff7f849c
export TEXT=0xffcdd6f4
export SUBTEXT=0xffa6adc8
export BLUE=0xff89b4fa
export LAVENDER=0xffb4befe
export SAPPHIRE=0xff74c7ec
export GREEN=0xffa6e3a1
export YELLOW=0xfff9e2af
export PEACH=0xfffab387
export PINK=0xfff5c2e7
export MAUVE=0xffcba6f7
export RED=0xfff38ba8
export TRANSPARENT=0x00000000

# Quickshell's ModuleButton is 25px tall inside a 32px bar, with the 14x2
# indicator pinned to the button's bottom edge.
export INDICATOR_WIDTH=14
export INDICATOR_HEIGHT=2
export INDICATOR_Y_OFFSET=-11

# components/BarDivider.qml: a 1x14 surface1 line in a 7px-wide slot.
#
# Drawn as a box-drawing glyph rather than a 1px background: sketchybar ignores
# an item's padding_left/right for layout whenever `width` is set explicitly,
# which left the line flush against its neighbour's glyph. A glyph keeps normal
# padding behaviour and takes its height from the font.
# BarDivider is 3px either side of the line, but the padding here is asymmetric
# on purpose. sketchybar sizes a glyph item from the glyph's ink (~1px for a box
# drawing character) while still rendering it with the font's full advance, so
# the line lands about 3.5px right of where the padding implies. Measured
# against the volume glyph, 0/6 yields 8.5px either side, matching Quickshell's
# 8px. Verify by flagging the items a unique icon.color and reading back pixels.
export DIVIDER_PADDING_LEFT=0
export DIVIDER_PADDING_RIGHT=6

# Quickshell draws BarDivider in solid surface1. That works on Linux because the
# bar composites dark, making the line slightly lighter than its background. The
# macOS bar sits over a lighter wallpaper and composites to roughly #77837F, so
# solid surface1 inverts into a heavy dark bar. Half alpha keeps it a hairline.
export DIVIDER_COLOR=0x8045475a

# BarGroup itemSpacing: 3px between each child of the right group, including
# between a divider and the module next to it.
export MODULE_SPACING=3

# StatusIsland's StatusButton uses horizontalPadding 5 when iconOnly.
export STATUS_PADDING=5

# Glyphs, taken from the Quickshell modules by codepoint so they cannot drift.
export GLYPH_BAT_CHARGING="󰂄"
export GLYPH_BAT_FULL="󰁹"
export GLYPH_BAT_90=""
export GLYPH_BAT_65=""
export GLYPH_BAT_40=""
export GLYPH_BAT_15=""
export GLYPH_BAT_LOW=""
export GLYPH_VOL_MUTED=""
export GLYPH_VOL_HEADPHONES=""
export GLYPH_VOL_HIGH=""
export GLYPH_VOL_MID=""
export GLYPH_VOL_LOW=""
export GLYPH_BT_ON=""
export GLYPH_BT_OFF="󰂲"
export GLYPH_WIFI_4="󰤨"
export GLYPH_WIFI_3="󰤥"
export GLYPH_WIFI_2="󰤢"
export GLYPH_WIFI_1="󰤟"
export GLYPH_WIFI_0="󰤯"
export GLYPH_WIFI_OFF="󰖪"
export GLYPH_ETHERNET="󰀂"
export GLYPH_IDLE_INHIBITED="󰅶"
export GLYPH_IDLE_NORMAL="󰛊"
export GLYPH_CALENDAR="󰃭"
export GLYPH_AI="󱙺"
export GLYPH_POWER="󰐥"
export GLYPH_TAILSCALE="󰖂"
export GLYPH_MIC_MUTED="󰍭"
export GLYPH_MIC_ON="󰍬"
export GLYPH_FOCUS="󰌵"
export GLYPH_DIVIDER="│"
export GLYPH_CLOCK="󰥔"
