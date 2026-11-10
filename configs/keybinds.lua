-- ~/.config/hypr/keybinds.lua
-- Replaces bind = / bindm = / binde = from the old .conf

local mod = "SUPER"
local terminal = "alacritty"
local browser = "firefox"

-- Active shell stack from ~/.config/hypr/shell.lua (HM-managed).
-- Falls back to "waybar" if the file is missing.
local ok, shell = pcall(require, "shell")
if not ok then shell = "waybar" end

-- App launchers
hl.bind(mod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + SHIFT + RETURN", hl.dsp.exec_cmd(browser))

-- Window management
hl.bind(mod .. " + Q", hl.dsp.window.close())
hl.bind(mod .. " + M", hl.dsp.exit())
hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + P", hl.dsp.window.pseudo())
hl.bind(mod .. " + ALT + J", hl.dsp.layout("togglesplit"))

-- Shell-specific: launcher + lock
if shell == "dankshell" then
    hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd("dms ipc call spotlight toggle"))
    hl.bind(mod .. " + x", hl.dsp.exec_cmd("dms ipc call lock lock"))
    hl.bind(mod .. " + N", hl.dsp.exec_cmd("dms ipc call notifications toggle"))
    hl.bind(mod .. " + comma", hl.dsp.exec_cmd("dms ipc call settings focusOrToggle"))
    hl.bind(mod .. " + ALT + V", hl.dsp.exec_cmd("dms ipc call clipboard toggle"))
    hl.bind(mod .. " + SHIFT + M", hl.dsp.exec_cmd("dms ipc call processlist focusOrToggle"))
else
    hl.bind(mod .. " + SPACE", hl.dsp.exec_cmd("wofi --show drun"))
    hl.bind(mod .. " + x", hl.dsp.exec_cmd("hyprlock"))
end

-- DPMS
hl.bind(mod .. " + SHIFT + O", hl.dsp.exec_cmd("hyprctl dispatch dpms off"))
hl.bind(mod .. " + ALT + L", hl.dsp.exec_cmd("hyprctl dispatch dpms on"))

-- Focus
hl.bind(mod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down", hl.dsp.focus({ direction = "down" }))

hl.bind(mod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + j", hl.dsp.focus({ direction = "down" }))
hl.bind(mod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + l", hl.dsp.focus({ direction = "right" }))

-- Move
hl.bind(mod .. " + SHIFT + h", hl.dsp.window.move({ direction = "left" }))
hl.bind(mod .. " + SHIFT + j", hl.dsp.window.move({ direction = "down" }))
hl.bind(mod .. " + SHIFT + k", hl.dsp.window.move({ direction = "up" }))
hl.bind(mod .. " + SHIFT + l", hl.dsp.window.move({ direction = "right" }))

-- Workspaces 1..9
for i = 1, 9 do
    hl.bind(mod .. " + " .. i, hl.dsp.focus({ workspace = tostring(i) }))
    hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = tostring(i) }))
end

-- Workspace 10
hl.bind(mod .. " + 0", hl.dsp.focus({ workspace = "10" }))
hl.bind(mod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = "10" }))

-- Special workspaces
hl.bind(mod .. " + ALT + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
hl.bind(mod .. " + ALT + O", hl.dsp.workspace.toggle_special("obsidian"))
hl.bind(mod .. " + ALT + T", hl.dsp.workspace.toggle_special("telegram"))

-- Mouse wheel workspace switch
hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Mouse drag / resize (replaces bindm = SUPER, mouse:272/273, ...)
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Screenshots (no modifier)
hl.bind("Print", hl.dsp.exec_cmd('grim -g "$(slurp)" - | wl-copy'))
hl.bind("SHIFT + Print", hl.dsp.exec_cmd('grim -g "$(slurp)" ~/Pictures/screenshot-$(date +%Y%m%d-%H%M%S).png'))

-- Media keys: volume/brightness go through DMS for the OSD; playerctl in both shells
if shell == "dankshell" then
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("dms ipc call audio increment 3"))
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("dms ipc call audio decrement 3"))
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("dms ipc call audio mute"))
    hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("dms ipc call brightness increment 5"))
    hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("dms ipc call brightness decrement 5"))
else
    hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"))
    hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"))
    hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
    hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl set +5%"))
    hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl set 5%-"))
end

hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"))
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"))
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"))

-- Keybind helper
hl.bind(mod .. " + TAB", hl.dsp.exec_cmd("hypr-binds"))
