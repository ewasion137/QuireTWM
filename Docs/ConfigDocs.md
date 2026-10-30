# QuireTWM Configuration Reference

QuireTWM is configured via a single Lua script located at:
```text
%USERPROFILE%\.quire\config.lua
```

Changes reload automatically on file save without restarting the process.

Also the CONFIG GENERATOR is here: https://ewasion137.github.io/Quire

---

## Table of Contents
1. [Layout & Performance](#1-layout--performance)
2. [Color Palette](#2-color-palette)
3. [Spring Physics Engine](#3-spring-physics-engine)
4. [Touchpad Gestures](#4-touchpad-gestures)
5. [Window Rules (Floating)](#5-window-rules-floating)
6. [Keybindings & API](#6-keybindings--api)
7. [Multi-Monitor Support](#7-multi-monitor-support)
8. [Built-in Launcher](#8-built-in-launcher)
9. [Animation Settings](#9-animation-settings)
10. [Complete Example `config.lua`](#10-complete-example-configlua)

---

## 1. Layout & Performance

Control monitor refresh sync, spacing, corner rounding and column ratios:

```lua
-- Target framerate limit (set 0 to sync with monitor refresh rate automatically)
Quire.config.fps_cap = 0

-- Inner spacing between adjacent tiled windows (pixels)
Quire.config.gaps_in = 10

-- Outer margin between windows and screen edges (pixels)
Quire.config.gaps_out = 14

-- Corner rounding radius for borders (Direct2D hardware overlay)
Quire.config.rounding = 8

-- Border line thickness (pixels)
Quire.config.border_size = 2

-- Default column width ratio relative to screen width (0.1 to 1.0)
Quire.config.default_column_width = 1.0
```

---

## 2. Color Palette

Window borders and HUD elements are rendered via Direct2D.  
Colors use normalized RGBA tables with float values from `0.0` to `1.0`:

```lua
Quire.config.border_active   = { 0.54, 0.71, 0.98, 1.0 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.6 }
```

---

## 3. Spring Physics Engine

Horizontal ribbon gliding and vertical workspace transitions are driven by numerical spring physics:

```lua
Quire.config.spring = {
    stiffness = 180,
    damping   = 22,
    mass      = 1.0
}
```

---

## 4. Touchpad Gestures

QuireTWM captures native Precision Touchpad horizontal swipes out of the box.  
Swiping two fingers left or right smoothly glides the ribbon camera across your active workspace columns in real time.

---

## 5. Window Rules (Floating)

Define programs that should open as floating windows by title, process name or Win32 class:

```lua
table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")
table.insert(Quire.window_rules.float, "NVIDIA GeForce Experience")
```

---

## 6. Keybindings & API

Keybindings are registered via `Quire.bind(chord, callback)`.

### Core API Methods

| Function | Action |
| :--- | :--- |
| `Quire.cycle_workspace(step)` | Relative workspace switch (`-1` for previous, `1` for next). |
| `Quire.switch_workspace(id)` | Switch camera directly to workspace `id` (1 to 9). |
| `Quire.move_to_workspace(id)` | Send focused client to workspace `id`. |
| `Quire.focus_direction(dir)` | Shift focus (`"left"`, `"right"`, `"up"` or `"down"`). |
| `Quire.move_column(dir)` | Swap current column with neighboring column. |
| `Quire.cycle_column_preset()` | Cycle width presets (`100%` -> `66%` -> `50%`). |
| `Quire.move_window_to_monitor(dir)` | Migrate active window to neighboring monitor (`"left"` or `"right"`). |
| `Quire.toggle_floating()` | Toggle floating state for active client. |
| `Quire.toggle_fullscreen()` | Toggle fullscreen view. |
| `Quire.save_session()` | Save current window positions to session cache. |
| `Quire.restore_session()` | Restore saved window layout across workspaces. |
| `wm.close_window(hwnd)` | Close window handle safely. |
| `wm.spawn(path)` | Launch an external program in isolated sandbox. |
| `launcher.toggle()` | Open or close quick app menu. |
| `launcher.commit()` | Launch currently highlighted app menu entry. |

---

## 7. Multi-Monitor Support

QuireTWM allows migrating windows between screens using `Quire.move_window_to_monitor(direction)`.  
Moving a client automatically shifts its coordinates to the target display's working bounds:

```lua
Quire.bind("Alt+Ctrl+H", function() Quire.move_window_to_monitor("left") end)
Quire.bind("Alt+Ctrl+L", function() Quire.move_window_to_monitor("right") end)
```

---

## 8. Built-in Launcher

Configure entries for the overlay launcher triggered via `Alt+Space`:

```lua
Quire.apps = {
    { name = "Terminal",      path = "cmd.exe" },
    { name = "File Explorer", path = "explorer.exe" },
    { name = "Code Editor",   path = "code.cmd" },
    { name = "Browser",       path = "firefox.exe" }
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
    if Quire.launcher_active then launcher.toggle() end
end)
```

---

## 9. Animation Settings

Configure animation behaviors, idle border pulse effects and exit styles:

```lua
-- Idle border effects: "pulse", "heartbeat", "shake", "flash", "wobble" or "none"
Quire.config.idle_mode = "pulse"

-- Window close effects: "scale", "slide", "fold" or "curtain"
Quire.config.close_anim = "scale"

-- Transition easing curve: "back", "elastic", "bounce", "ease_in_out" or "linear"
Quire.config.move_easing = "back"

Alt-Tab Overview Zoom

Holding Alt-Tab automatically scales the active workspace layout down to 72% towards the screen center, giving you a Mission-Control style overview of adjacent ribbon columns while switching windows.

---

## 10. Complete Example `config.lua`

```lua
-- QuireTWM Configuration
-- Location: %USERPROFILE%\.quire\config.lua

Quire.config.fps_cap = 0
Quire.config.gaps_in = 8
Quire.config.gaps_out = 14
Quire.config.rounding = 8
Quire.config.border_size = 2
Quire.config.default_column_width = 1.0

Quire.config.border_active = { 0.54, 0.71, 0.98, 1.0 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.6 }

Quire.config.spring = {
    stiffness = 180,
    damping = 22,
    mass = 1.0
}

Quire.config.idle_mode = "heartbeat"
Quire.config.close_anim = "scale"
Quire.config.move_easing = "elastic"

table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")

-- Relative workspace switching
Quire.bind("Alt+Q", function() Quire.cycle_workspace(-1) end)
Quire.bind("Alt+E", function() Quire.cycle_workspace(1) end)

-- Column focus navigation
Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

-- Column movement
Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)
Quire.bind("Alt+D", Quire.cycle_column_preset)

-- Multi-monitor migration
Quire.bind("Alt+Ctrl+H", function() Quire.move_window_to_monitor("left") end)
Quire.bind("Alt+Ctrl+L", function() Quire.move_window_to_monitor("right") end)

-- Window states
Quire.bind("Alt+V", Quire.toggle_floating)
Quire.bind("Alt+F", Quire.toggle_fullscreen)

-- Session controls
Quire.bind("Alt+Shift+S", Quire.save_session)
Quire.bind("Alt+Shift+R", Quire.restore_session)

-- Launcher setup
Quire.apps = {
    { name = "Terminal", path = "cmd.exe" },
    { name = "Explorer", path = "explorer.exe" }
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
    if Quire.launcher_active then launcher.toggle() end
end)

-- Direct workspace keybindings
for i = 1, 9 do
    Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
    Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
end
```