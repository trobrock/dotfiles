-- https://wiki.hypr.land/Configuring/Basics/Binds/

local terminal = "uwsm app -- ghostty"
local browser = "uwsm app -- chromium"
local file_manager = "uwsm app -- dolphin"
local password_manager = "1password"

hl.bind("SUPER + SHIFT + P", hl.dsp.window.pseudo())
hl.bind("SUPER + P", hl.dsp.layout("togglesplit"))
hl.bind("SUPER + F", hl.dsp.window.fullscreen())

hl.bind("SUPER + Q", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + W", hl.dsp.window.close())
hl.bind("SUPER + Space", hl.dsp.global("quickshell:launcher"))
hl.bind("SUPER + Return", hl.dsp.exec_cmd(browser))

-- Lock and power menu
hl.bind("SUPER + ESCAPE", hl.dsp.exec_cmd("/usr/bin/hyprlock"))
hl.bind("SUPER + SHIFT + ESCAPE", hl.dsp.global("quickshell:power-menu"))
hl.bind("SUPER + CTRL + ESCAPE", hl.dsp.global("quickshell:power-menu"))

hl.bind("SUPER + E", hl.dsp.exec_cmd(file_manager))
hl.bind("SUPER + V", hl.dsp.window.float())
hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal .. " -e btop"))
hl.bind("SUPER + D", hl.dsp.exec_cmd(terminal .. " -e lazydocker"))
hl.bind("SUPER + slash", hl.dsp.exec_cmd(password_manager))
hl.bind("SUPER + B", hl.dsp.global("quickshell:bluetooth"))
hl.bind("SUPER + N", hl.dsp.global("quickshell:wifi"))
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("uwsm app -- /opt/google/chrome/chrome --app=https://3.basecamp.com/5732210"))

-- Groups
hl.bind("SUPER + g", hl.dsp.group.toggle())
hl.bind("SUPER + CTRL + l", hl.dsp.group.next())
hl.bind("SUPER + CTRL + h", hl.dsp.group.prev())

-- Clipboard history
hl.bind("SUPER + SHIFT + C", hl.dsp.global("quickshell:clipboard"))

-- Notifications
hl.bind("SUPER + comma", hl.dsp.global("quickshell:notifications-dismiss"))
hl.bind("SUPER + SHIFT + comma", hl.dsp.global("quickshell:notifications-clear"))
hl.bind("SUPER + CTRL + comma", hl.dsp.global("quickshell:notifications-dnd"))

-- Move focus with Super + vim keys
local directions = { h = "left", j = "down", k = "up", l = "right" }
for key, direction in pairs(directions) do
    hl.bind("SUPER + " .. key, hl.dsp.focus({ direction = direction }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ direction = direction, group_aware = true }))
end

-- Switch workspaces and move windows with Super + [1-9]
for workspace = 1, 9 do
    local key = tostring(workspace)
    hl.bind("SUPER + " .. key, hl.dsp.focus({ workspace = workspace }))
    hl.bind("SUPER + SHIFT + " .. key, hl.dsp.window.move({ workspace = workspace }))
end

-- Screenshots
hl.bind("code:110", hl.dsp.exec_cmd("hyprshot -m region"))
hl.bind("SHIFT + code:110", hl.dsp.exec_cmd("hyprshot -m window"))
hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m region"))
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd("hyprshot -m window"))

-- Screen recording (re-press any recording bind to stop)
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("~/.config/scripts/record-screen mp4"))
hl.bind("SUPER + SHIFT + G", hl.dsp.exec_cmd("~/.config/scripts/record-screen gif"))
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd("~/.config/scripts/record-screen mp4 --with-desktop-audio --with-microphone-audio --with-webcam"))

-- Special workspaces
hl.bind("SUPER + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind("SUPER + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind("SUPER + TAB", hl.dsp.workspace.toggle_special("typingmind"))
hl.bind("SUPER + SHIFT + TAB", hl.dsp.window.move({ workspace = "special:typingmind" }))

-- Scroll through existing workspaces
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Move and resize windows with the mouse
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Multimedia keys
local repeat_locked = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.global("quickshell:volume-up"), repeat_locked)
hl.bind("XF86AudioLowerVolume", hl.dsp.global("quickshell:volume-down"), repeat_locked)
hl.bind("XF86AudioMute", hl.dsp.global("quickshell:output-mute"), repeat_locked)
hl.bind("XF86AudioMicMute", hl.dsp.global("quickshell:microphone-mute"), repeat_locked)
hl.bind("XF86MonBrightnessUp", hl.dsp.global("quickshell:brightness-up"), repeat_locked)
hl.bind("XF86MonBrightnessDown", hl.dsp.global("quickshell:brightness-down"), repeat_locked)

hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Headphones
hl.bind("SUPER + SHIFT + CTRL + H", hl.dsp.exec_cmd("bluetoothctl connect 04:00:6E:D6:E3:59"))

-- VoxType: ignore modifiers so the dedicated key always works.
hl.bind("code:134", hl.dsp.exec_cmd("/usr/local/bin/voxtype record toggle"), { ignore_mods = true })
