# QuireTWM Configuration Reference

QuireTWM is configured through a single Lua file located at:
```text
%USERPROFILE%\.quire\config.lua
```

Changes reload automatically upon saving the file without restarting the application.

Configuration Generator: https://ewasion137.github.io/Quire

---

## Table of Contents
1. [Layout & General Settings](#1-layout--general-settings)
2. [Color Palette & Theme](#2-color-palette--theme)
3. [Spring Physics Engine](#3-spring-physics-engine)
4. [Scratchpad](#4-scratchpad)
5. [Overview Mode](#5-overview-mode)
6. [Mouse & Touchpad Gestures](#6-mouse--touchpad-gestures)
7. [Window Rules](#7-window-rules)
8. [Keybindings & API Reference](#8-keybindings--api-reference)
9. [Animation & Visual Effects](#9-animation--visual-effects)
10. [IPC Interface](#10-ipc-interface)
11. [Lua Event Hooks](#11-lua-event-hooks)
12. [Complete Example `config.lua`](#12-complete-example-configlua)

---

## 1. Layout & General Settings

Control frame rates, gaps, corner rounding, column widths and focus behavior:

```lua
-- Target framerate limit (0 matches your monitor refresh rate automatically)
Quire.config.fps_cap = 0

-- Inner spacing between adjacent tiled windows in pixels
Quire.config.gaps_in = 8

-- Outer margin between windows and work area edges in pixels
Quire.config.gaps_out = 14

-- Border corner rounding radius in pixels
Quire.config.rounding = 10

-- Border outline thickness in pixels
Quire.config.border_size = 2

-- Default column width ratio relative to screen width (0.1 to 1.0)
Quire.config.default_column_width = 1.0

-- Automatic focus change on mouse hover
Quire.config.focus_follows_mouse = false
```

---

## 2. Color Palette & Theme

Window borders, heads-up displays, launcher items and Alt-Tab cards are drawn via hardware-accelerated Direct2D. Colors use normalized RGBA tables with float values from `0.0` to `1.0`:

```lua
-- Border colors
Quire.config.border_active   = { 0.54, 0.71, 0.98, 1.00 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.60 }

-- Global UI elements
Quire.theme.font_family         = "Segoe UI Variable"
Quire.theme.bg_color            = { 0.05, 0.05, 0.08, 0.92 }
Quire.theme.accent_color        = { 0.54, 0.71, 0.98, 1.00 }
Quire.theme.text_color          = { 0.90, 0.90, 0.95, 1.00 }
Quire.theme.text_dim            = { 0.55, 0.55, 0.65, 0.80 }
```

---

## 3. Spring Physics Engine

Horizontal ribbon camera motion and vertical workspace transitions run on second-order spring dynamics:

```lua
Quire.config.spring = {
    stiffness = 160,
    damping   = 22,
    mass      = 1.0
}
```

Higher stiffness creates faster movement, while higher damping prevents oscillations.

---

## 4. Scratchpad

A scratchpad allows dropping down an overlay utility window from the top edge of your screen. You can set the default program command, toggle visibility or pin any existing window into the scratchpad slot:

```lua
-- Program command executed when toggling an uninitialized scratchpad
Quire.config.scratchpad_cmd = "alacritty.exe"

-- Toggle scratchpad drop-down
Quire.bind("Alt+Grave", Quire.toggle_scratchpad)

-- Turn focused window into scratchpad or return it back to tiling
Quire.bind("Alt+Shift+Grave", Quire.mark_scratchpad)
```

Hiding the scratchpad restores focus to your previous window.

---

## 5. Overview Mode

Overview scales all workspace columns down to 72% size centered vertically on your screen. This gives you a clear panoramic view of your entire ribbon:

```lua
-- Toggle overview zoom
Quire.bind("Alt+O", Quire.toggle_overview)
```

While in Overview mode:
- Vertical mouse wheel rolls smoothly glide the ribbon horizontally.
- Directional focus hotkeys automatically center the camera on the target column.
- Re-triggering `Alt+O` restores full view and focuses the selected window.

---

## 6. Mouse & Touchpad Gestures

QuireTWM reads Precision Touchpad and mouse inputs directly:

- **Touchpad Horizontal Swipe**: Two-finger horizontal panning scrolls the camera across your workspace columns in real time.
- **Touchpad Speed Multiplier**: Adjust swipe sensitivity via `Quire.config.trackpad_speed = 1.2`.
- **Workspace Wheel Scrolling**: Rolling your mouse wheel while holding `Ctrl` or `Alt+Ctrl` cycles through workspaces.

---

## 7. Window Rules

Define applications that should bypass automatic tiling and open directly as floating windows. Matches process names, window titles and Win32 class strings:

```lua
table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")
table.insert(Quire.window_rules.float, "NVIDIA GeForce Experience")
```

---

## 8. Keybindings & API Reference

Key combinations are registered using `Quire.bind(chord, callback)`. Supported modifiers are `Alt`, `Ctrl`, `Shift` and `Super` (or `Win`).

### Window Management

| Method | Description |
| :--- | :--- |
| `Quire.focus_direction(dir)` | Move focus (`"left"`, `"right"`, `"up"` or `"down"`). |
| `Quire.move_column(dir)` | Swap current column position (`"left"` or `"right"`). |
| `Quire.cycle_column_preset()` | Cycle width presets: 100%, 66% and 50%. |
| `Quire.toggle_floating()` | Toggle floating state for active window. |
| `Quire.toggle_fullscreen()` | Toggle fullscreen view for active window. |
| `Quire.safe_close_window(hwnd)` | Close window using smooth animated exit. |
| `Quire.move_window_to_monitor(dir)` | Move active window to adjacent display (`"left"` or `"right"`). |

### Workspaces & Session

| Method | Description |
| :--- | :--- |
| `Quire.switch_workspace(id)` | Switch directly to workspace number (1 to 9). |
| `Quire.cycle_workspace(step)` | Switch relative workspace (`-1` previous, `1` next). |
| `Quire.move_to_workspace(id)` | Transfer active window to workspace number (1 to 9). |
| `Quire.save_session()` | Save current column and workspace structure to file. |
| `Quire.restore_session()` | Reopen and place saved layout across workspaces. |
| `Quire.reload_config()` | Force reload configuration file. |

### System & Helper Methods

| Method | Description |
| :--- | :--- |
| `wm.spawn(path)` | Launch process using system shell. |
| `wm.close_window(hwnd)` | Send immediate close message to window handle. |
| `wm.focus_window(hwnd)` | Bring window handle to foreground. |
| `wm.get_window_title(hwnd)` | Query window title text string. |
| `wm.get_process_name(hwnd)` | Query process executable name string. |
| `wm.get_class_name(hwnd)` | Query Win32 class string. |
| `wm.get_work_area()` | Return work area bounds: `x, y, w, h`. |
| `wm.get_screen_size()` | Return display resolution: `w, h`. |

---

## 9. Animation & Visual Effects

Choose easing curves, idle border motion and closing animations:

```lua
-- Transition curves: "spring", "back", "elastic", "bounce", "ease_in_out", "ease_in", "ease_out" or "linear"
Quire.config.move_easing = "spring"

-- Idle border animations: "pulse", "heartbeat", "shake", "flash", "wobble" or "none"
Quire.config.idle_mode = "pulse"

-- Window closing animations: "scale", "slide", "fold" or "curtain"
Quire.config.close_anim = "scale"
```

---

## 10. IPC Interface

QuireTWM exposes a local named pipe at `\\.\pipe\quire`. Send plain text strings to trigger actions or read status information from external scripts and bars:

```powershell
# Example PowerShell command
[System.IO.File]::WriteAllText("\\.\pipe\quire", "workspace 2")
```

### Supported IPC Commands

| Command | Action |
| :--- | :--- |
| `focus left` / `right` / `up` / `down` | Shift focus in specified direction. |
| `move left` / `right` | Swap column in specified direction. |
| `workspace <num>` | Switch active workspace. |
| `movetoworkspace <num>` | Move active window to workspace. |
| `togglefloating` | Toggle floating state. |
| `fullscreen` | Toggle fullscreen state. |
| `preset` | Cycle column width preset. |
| `close` | Close currently focused window. |
| `reload` | Reload configuration. |
| `clients` | List all tracked windows across workspaces. |

---

## 11. Lua Event Hooks

Attach custom callbacks to engine lifecycle events:

```lua
-- Window created or added
Quire.hooks.on_window_open = function(hwnd, title, class)
end

-- Window destroyed or closed
Quire.hooks.on_window_close = function(hwnd)
end

-- Window focused
Quire.hooks.on_window_focus = function(hwnd, title, class)
end

-- Workspace changed
Quire.hooks.on_workspace_change = function(old_ws, new_ws)
end

-- Custom border drawing override (return true to skip built-in border)
Quire.hooks.on_draw_window_border = function(ctx)
    return false
end

-- Custom HUD rendering override
Quire.hooks.on_draw_hud = function(ctx)
end
```

---

## 12. Complete Example `config.lua`

```lua
-- QuireTWM Configuration
-- File: %USERPROFILE%\.quire\config.lua

Quire.config.fps_cap = 0
Quire.config.gaps_in = 8
Quire.config.gaps_out = 14
Quire.config.rounding = 10
Quire.config.border_size = 2
Quire.config.default_column_width = 1.0
Quire.config.focus_follows_mouse = false
Quire.config.scratchpad_cmd = "alacritty.exe"
Quire.config.trackpad_speed = 1.2

Quire.config.border_active = { 0.54, 0.71, 0.98, 1.00 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.60 }

Quire.config.spring = {
    stiffness = 160,
    damping = 22,
    mass = 1.0
}

Quire.config.idle_mode = "pulse"
Quire.config.close_anim = "scale"
Quire.config.move_easing = "spring"

table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")

-- Focus navigation
Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

-- Column layout
Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)
Quire.bind("Alt+D", Quire.cycle_column_preset)

-- Window controls
Quire.bind("Alt+V", Quire.toggle_floating)
Quire.bind("Alt+F", Quire.toggle_fullscreen)
Quire.bind("Alt+Shift+Q", function()
    if Quire.focused_window then
        Quire.safe_close_window(Quire.focused_window)
    end
end)

-- Workspace cycling
Quire.bind("Alt+Q", function() Quire.cycle_workspace(-1) end)
Quire.bind("Alt+E", function() Quire.cycle_workspace(1) end)

-- Overview and Scratchpad
Quire.bind("Alt+O", Quire.toggle_overview)
Quire.bind("Alt+Grave", Quire.toggle_scratchpad)
Quire.bind("Alt+Shift+Grave", Quire.mark_scratchpad)

-- Display migration
Quire.bind("Alt+Ctrl+H", function() Quire.move_window_to_monitor("left") end)
Quire.bind("Alt+Ctrl+L", function() Quire.move_window_to_monitor("right") end)

-- Session management
Quire.bind("Alt+Shift+S", Quire.save_session)
Quire.bind("Alt+Shift+R", Quire.restore_session)

-- Built-in launcher setup
Quire.apps = {
    { name = "Terminal", path = "cmd.exe" },
    { name = "Explorer", path = "explorer.exe" },
    { name = "Task Manager", path = "taskmgr.exe" }
}

Quire.bind("Alt+Space", launcher.toggle)
Quire.bind("Alt+Return", function()
    if Quire.launcher_active then
        launcher.commit()
    else
        wm.spawn("cmd.exe")
    end
end)
Quire.bind("Alt+Escape", function()
    if Quire.launcher_active then
        launcher.toggle()
    end
end)

-- Numbered workspace keybindings (1 to 9)
for i = 1, 9 do
    Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
    Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
end
```