# QuireTWM Config Guide

QuireTWM reads its settings from one Lua file at:

```text
%USERPROFILE%\.quire\config.lua
```

When you save this file, QuireTWM reloads your settings right away without a restart.

Config Generator: https://ewasion137.github.io/Quire

---

## Table of Contents

1. [General Settings](#1-general-settings)
2. [Colors and Theme](#2-colors-and-theme)
3. [Spring Motion](#3-spring-motion)
4. [Scratchpad](#4-scratchpad)
5. [Overview Mode](#5-overview-mode)
6. [Mouse and Touchpad](#6-mouse-and-touchpad)
7. [Window Rules](#7-window-rules)
8. [Keybindings and Functions](#8-keybindings-and-functions)
9. [Animations](#9-animations)
10. [Autostart and App Launcher](#10-autostart-and-app-launcher)
11. [IPC Commands](#11-ipc-commands)
12. [Lua Hooks](#12-lua-hooks)
13. [Full Example `config.lua`](#13-full-example-configlua)

---

## 1. General Settings

Set frame rate, gaps, rounded corners, borders, opacity and UI widgets:

```lua
-- Max FPS (0 matches your monitor refresh rate)
Quire.config.fps_cap = 0

-- Space between tiled windows in pixels
Quire.config.gaps_in = 8

-- Space between windows and screen edges in pixels
Quire.config.gaps_out = 14

-- Corner rounding in pixels
Quire.config.rounding = 10

-- Border width in pixels
Quire.config.border_size = 2

-- Starting width for new columns (0.1 to 1.0)
Quire.config.default_column_width = 1.0

-- Focus windows when the mouse moves over them
Quire.config.focus_follows_mouse = false

-- Opacity for unfocused windows (0.2 to 1.0)
Quire.config.inactive_opacity = 0.90

-- Remove gaps when only one window is open on a workspace
Quire.config.smart_gaps = true

-- Remove borders when only one window is open on a workspace
Quire.config.smart_borders = false

-- Show or hide the top Isle widget and the bottom minimap
Quire.config.enable_isle = true
Quire.config.enable_minimap = true
```

---

## 2. Colors and Theme

Borders, the Isle bar, the minimap, the launcher and the Alt-Tab switcher use colors made of four numbers from `0.0` to `1.0` for red, green, blue and alpha:

```lua
-- Window border colors
Quire.config.border_active   = { 0.54, 0.71, 0.98, 1.00 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.60 }

-- Global theme colors and font
Quire.theme.font_family  = "Segoe UI Variable"
Quire.theme.bg_color     = { 0.05, 0.05, 0.08, 0.92 }
Quire.theme.accent_color = { 0.54, 0.71, 0.98, 1.00 }
Quire.theme.text_color   = { 0.90, 0.90, 0.95, 1.00 }
Quire.theme.text_dim     = { 0.55, 0.55, 0.65, 0.80 }
```

---

## 3. Spring Motion

Window movement and workspace switches use spring physics:

```lua
Quire.config.spring = {
    stiffness = 170,
    damping   = 24,
    mass      = 1.0
}
```

Higher `stiffness` makes windows move faster. Higher `damping` stops them from bouncing.

---

## 4. Scratchpad

The scratchpad is a floating window that slides down from the top of the screen. You can set which app it opens, toggle it or turn any open window into your scratchpad:

```lua
-- App to open when no scratchpad window exists yet
Quire.config.scratchpad_cmd = "alacritty.exe"

-- Show or hide the scratchpad
Quire.bind("Alt+Grave", Quire.toggle_scratchpad)

-- Turn the active window into the scratchpad or put it back into tiling
Quire.bind("Alt+Shift+Grave", Quire.mark_scratchpad)
```

When you hide the scratchpad, focus goes back to the window you were using before.

---

## 5. Overview Mode

Overview zooms all columns out to 72% size so you can see your whole workspace at once:

```lua
Quire.bind("Alt+O", Quire.toggle_overview)
```

In Overview mode:
- Scrolling the mouse wheel moves the view left and right.
- Focus keys jump between windows and center the view on them.
- Pressing `Alt+O` again returns to normal view and focuses the selected window.

---

## 6. Mouse and Touchpad

QuireTWM supports touchpad gestures and mouse wheel shortcuts:

- **Two-finger horizontal swipe**: Scrolls left and right across columns.
- **Touchpad speed**: Set swipe speed with `Quire.config.trackpad_speed = 1.2`.
- **Workspace scroll**: Hold `Ctrl` or `Alt+Ctrl` and scroll to switch workspaces.

---

## 7. Window Rules

Add app names, window titles or Win32 class names to `Quire.window_rules.float` to keep those windows floating:

```lua
table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")
table.insert(Quire.window_rules.float, "NVIDIA GeForce Experience")
```

---

## 8. Keybindings and Functions

Add keybindings with `Quire.bind(keys, callback)`. You can use `Alt`, `Ctrl`, `Shift` and `Super` (or `Win`) as modifiers.

### Windows and Columns

| Function | What it does |
| :--- | :--- |
| `Quire.focus_direction(dir)` | Move focus (`"left"`, `"right"`, `"up"` or `"down"`). |
| `Quire.move_column(dir)` | Move the active column (`"left"` or `"right"`). |
| `Quire.consume_window(dir)` | Pull a window into the active column (`"left"` or `"right"`). |
| `Quire.expel_window(dir)` | Push the active window out into its own column (`"left"` or `"right"`). |
| `Quire.resize_column(delta)` | Change the active column width by a number like `0.08` or `-0.08`. |
| `Quire.cycle_column_preset()` | Switch column width between 100%, 66% and 50%. |
| `Quire.toggle_floating()` | Switch the active window between tiled and floating. |
| `Quire.toggle_fullscreen()` | Make the active window fill the screen or go back to normal. |
| `Quire.safe_close_window(hwnd)` | Close a window with a close animation. |
| `Quire.move_window_to_monitor(dir)` | Move the active window to another monitor (`"left"` or `"right"`). |

### Workspaces, Session and Launcher

| Function | What it does |
| :--- | :--- |
| `Quire.switch_workspace(id)` | Go to workspace `1` through `9`. |
| `Quire.cycle_workspace(step)` | Go to the next (`1`) or previous (`-1`) workspace. |
| `Quire.move_to_workspace(id)` | Send the active window to workspace `1` through `9`. |
| `Quire.save_session()` | Save open windows and workspaces to a file. |
| `Quire.restore_session()` | Reopen and place your saved layout. |
| `Quire.toggle_launcher()` | Open or close the app launcher. |
| `Quire.reload_config()` | Reload `config.lua`. |

### Window Helpers (`wm`)

| Function | What it does |
| :--- | :--- |
| `wm.spawn(path)` | Start an app or command. |
| `wm.close_window(hwnd)` | Close a window right away. |
| `wm.focus_window(hwnd)` | Focus a window. |
| `wm.get_window_title(hwnd)` | Get a window title. |
| `wm.get_process_name(hwnd)` | Get an app executable name. |
| `wm.get_class_name(hwnd)` | Get a Win32 class name. |
| `wm.get_work_area()` | Get usable screen area: `x, y, w, h`. |
| `wm.get_screen_size()` | Get full screen size: `w, h`. |

---

## 9. Animations

Pick how windows move, how active borders animate when idle and how windows close:

```lua
-- Movement curve: "spring", "linear", "ease_in", "ease_out", "ease_in_out",
-- "expo_out", "circ_out", "sine", "back", "bounce" or "elastic"
Quire.config.move_easing = "spring"

-- Duration in seconds when move_easing is set to a curve other than "spring"
Quire.config.move_duration = 0.28

-- Active border idle effect: "pulse", "breathe", "rainbow", "neon",
-- "heartbeat", "flash", "shake", "wobble" or "none"
Quire.config.idle_mode = "pulse"

-- Window close animation: "scale", "zoom", "slide", "pop", "crt", "fold" or "curtain"
Quire.config.close_anim = "scale"
```

---

## 10. Autostart and App Launcher

Run apps automatically when QuireTWM starts with `Quire.autostart`, and list apps for the launcher and tray menu in `Quire.apps`:

```lua
Quire.autostart = {
    "alacritty.exe"
}

Quire.apps = {
    { name = "Terminal", path = "cmd.exe" },
    { name = "Explorer", path = "explorer.exe" },
    { name = "Task Manager", path = "taskmgr.exe" }
}
```

---

## 11. IPC Commands

QuireTWM listens on the named pipe `\\.\pipe\quire`. External scripts and status bars can write plain text commands to it:

```powershell
[System.IO.File]::WriteAllText("\\.\pipe\quire", "workspace 2")
```

| Command | Action |
| :--- | :--- |
| `focus left` / `right` / `up` / `down` | Move focus. |
| `move left` / `right` | Move the active column. |
| `workspace <num>` | Switch to a workspace. |
| `movetoworkspace <num>` | Move the active window to a workspace. |
| `togglefloating` | Toggle floating on the active window. |
| `fullscreen` | Toggle fullscreen on the active window. |
| `preset` | Cycle column width preset. |
| `close` | Close the active window. |
| `reload` | Reload `config.lua`. |
| `clients` | List all tiled windows. |

---

## 12. Lua Hooks

Run your own Lua code when windows open, close, get focus, change workspaces or draw on screen:

```lua
Quire.hooks.on_window_open = function(hwnd, title, class)
end

Quire.hooks.on_window_close = function(hwnd)
end

Quire.hooks.on_window_focus = function(hwnd, title, class)
end

Quire.hooks.on_workspace_change = function(old_ws, new_ws)
end

-- Return true to skip drawing the default border
Quire.hooks.on_draw_window_border = function(ctx)
    return false
end

Quire.hooks.on_draw_hud = function(ctx)
end

Quire.hooks.on_post_render = function(now, sw, sh)
end
```

---

## 13. Full Example `config.lua`

```lua
-- QuireTWM Config
-- File: %USERPROFILE%\.quire\config.lua

Quire.config.fps_cap = 0
Quire.config.gaps_in = 8
Quire.config.gaps_out = 14
Quire.config.rounding = 10
Quire.config.border_size = 2
Quire.config.default_column_width = 1.0
Quire.config.focus_follows_mouse = false
Quire.config.inactive_opacity = 0.90
Quire.config.smart_gaps = true
Quire.config.smart_borders = false
Quire.config.enable_isle = true
Quire.config.enable_minimap = true
Quire.config.scratchpad_cmd = "alacritty.exe"
Quire.config.trackpad_speed = 1.2

Quire.config.border_active = { 0.54, 0.71, 0.98, 1.00 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.60 }

Quire.config.spring = {
    stiffness = 170,
    damping = 24,
    mass = 1.0
}

Quire.config.idle_mode = "pulse"
Quire.config.close_anim = "scale"
Quire.config.move_easing = "spring"
Quire.config.move_duration = 0.28

table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")

-- Focus
Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

-- Columns
Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)
Quire.bind("Alt+Comma", function() Quire.consume_window("left") end)
Quire.bind("Alt+Period", function() Quire.expel_window("right") end)
Quire.bind("Alt+-", function() Quire.resize_column(-0.08) end)
Quire.bind("Alt+=", function() Quire.resize_column(0.08) end)
Quire.bind("Alt+D", Quire.cycle_column_preset)

-- Windows
Quire.bind("Alt+V", Quire.toggle_floating)
Quire.bind("Alt+F", Quire.toggle_fullscreen)
Quire.bind("Alt+Shift+Q", function()
    if Quire.focused_window then
        Quire.safe_close_window(Quire.focused_window)
    end
end)

-- Workspaces
Quire.bind("Alt+Q", function() Quire.cycle_workspace(-1) end)
Quire.bind("Alt+E", function() Quire.cycle_workspace(1) end)

-- Overview and Scratchpad
Quire.bind("Alt+O", Quire.toggle_overview)
Quire.bind("Alt+Grave", Quire.toggle_scratchpad)
Quire.bind("Alt+Shift+Grave", Quire.mark_scratchpad)

-- Monitors
Quire.bind("Alt+Ctrl+H", function() Quire.move_window_to_monitor("left") end)
Quire.bind("Alt+Ctrl+L", function() Quire.move_window_to_monitor("right") end)

-- Session
Quire.bind("Alt+Shift+S", Quire.save_session)
Quire.bind("Alt+Shift+R", Quire.restore_session)

-- Launcher
Quire.apps = {
    { name = "Terminal", path = "cmd.exe" },
    { name = "Explorer", path = "explorer.exe" },
    { name = "Task Manager", path = "taskmgr.exe" }
}

Quire.bind("Alt+Space", Quire.toggle_launcher)
Quire.bind("Alt+Return", function()
    if Quire.launcher_active then
        launcher.commit()
    else
        wm.spawn("cmd.exe")
    end
end)
Quire.bind("Alt+Escape", function()
    if Quire.launcher_active then
        Quire.toggle_launcher()
    end
end)

-- Numbered workspaces (1 to 9)
for i = 1, 9 do
    Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
    Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
end
```
