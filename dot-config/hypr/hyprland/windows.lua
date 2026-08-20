-- https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

local desktop_monitor = "desc:BNQ BenQ RD280U 77R0278901Q"
for _, workspace in ipairs({ "1", "2", "3", "4", "6" }) do
    hl.workspace_rule({ workspace = workspace, monitor = desktop_monitor, persistent = true })
end
hl.workspace_rule({ workspace = "5", monitor = "eDP-1", persistent = true })

-- https://wiki.hypr.land/Configuring/Basics/Window-Rules/
hl.window_rule({
    name = "slack-workspace",
    match = { class = "Slack" },
    workspace = "3",
})

local music_and_todoist = "(chrome-music.youtube.com__-Default|chrome-app.todoist.com__app_today-Default)"
hl.window_rule({
    name = "music-and-todoist-group",
    match = { class = music_and_todoist },
    group = "set",
})
hl.window_rule({
    name = "music-and-todoist-workspace",
    match = { class = music_and_todoist },
    workspace = "5",
})
hl.window_rule({
    name = "sonos-workspace",
    match = { class = "(chrome-play.sonos.com__en-us_web-app-Default)" },
    workspace = "5",
})

hl.window_rule({
    name = "typingmind-workspace",
    match = { class = "chrome-www.typingmind.com__-Default" },
    workspace = "special:typingmind",
})
hl.window_rule({
    name = "basecamp-workspace",
    match = { class = "chrome-3.basecamp.com__5732210-Default" },
    workspace = "4",
})

hl.window_rule({
    name = "webcam-overlay",
    match = { title = "WebcamOverlay" },
    float = true,
    pin = true,
    no_initial_focus = true,
    no_dim = true,
    move = "(monitor_w-window_w-40) (monitor_h-window_h-40)",
})

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    name = "hide-google-meet-sharing-window",
    match = { title = "(.*)(meet\\.google\\.com)(.*)" },
    move = "9000 9000",
})
hl.window_rule({
    name = "hide-browser-sharing-notification",
    match = { title = ".*is sharing.*" },
    workspace = "special silent",
})
