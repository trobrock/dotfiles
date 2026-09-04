-- A Quake-style command deck dedicated to managing this dotfiles repository.
local width_share = 0.82
local height_share = 0.6
local top_margin = 0
local workspace = "special:dotfiles-agent"
local seed = "[workspace " .. workspace .. " silent] uwsm app -- ghostty --gtk-single-instance=false --class=com.trobrock.DotfilesNotch --working-directory=~/dev/personal/dotfiles --background-opacity=0.9 --window-padding-x=14 --window-padding-y=10 -e zsh -fc '[[ -r \"$HOME/.zsh_secrets\" ]] && source \"$HOME/.zsh_secrets\"; exec notch'"

hl.config({
    decoration = {
        dim_special = 0.68,
    },
})

hl.window_rule({
    name = "dotfiles-command-deck",
    match = { class = "com.trobrock.DotfilesNotch" },
    border_size = 0,
    rounding = 18,
    rounding_power = 3,
})

-- Size the workspace with dynamic gaps so the deck stays centered and keeps
-- the same proportions across monitor and scale changes.
local covering = nil
local function cover(gaps)
    if covering
        and covering.top == gaps.top
        and covering.right == gaps.right
        and covering.bottom == gaps.bottom
        and covering.left == gaps.left then
        return
    end

    covering = gaps
    hl.workspace_rule({
        workspace = workspace,
        gaps_in = 0,
        gaps_out = gaps,
        on_created_empty = seed,
    })
end

local function fit()
    local monitor = hl.get_active_monitor()
    if not monitor or not monitor.scale or monitor.scale <= 0 then
        return
    end

    local reserved = monitor.reserved
    local usable_width = monitor.width / monitor.scale - reserved.left - reserved.right
    local usable_height = monitor.height / monitor.scale - reserved.top - reserved.bottom
    local horizontal_margin = math.max(0, math.floor(usable_width * (1 - width_share) / 2))
    local deck_height = math.floor(usable_height * height_share)
    local bottom_margin = math.max(0, math.floor(usable_height - top_margin - deck_height))

    cover({
        top = top_margin,
        right = horizontal_margin,
        bottom = bottom_margin,
        left = horizontal_margin,
    })
end

cover({ top = top_margin, right = 0, bottom = 0, left = 0 })
fit()

hl.on("monitor.layout_changed", fit)
hl.on("monitor.focused", fit)

hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 3, bezier = "easeOutQuint", style = "slide top" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 2, bezier = "easeInOutCubic", style = "slide bottom" })
