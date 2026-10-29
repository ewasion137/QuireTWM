# QuireTWM Configuration Reference

QuireTWM is configured via a single Lua script located at:
```text
%USERPROFILE%\.quire\config.lua
```

Any changes made to this file are automatically reloaded on save without requiring a process restart.

---

## Table of Contents
1. [Layout & Geometry](#1-layout--geometry)
2. [Color Palette](#2-color-palette)
3. [Spring Physics Engine](#3-spring-physics-engine)
4. [Window Rules (Floating)](#4-window-rules-floating)
5. [Keybindings & API](#5-keybindings--api)
6. [Built-in Launcher](#6-built-in-launcher)
7. [Process Spawning & Sandboxing](#7-process-spawning--sandboxing)
8. [Complete Example `config.lua`](#8-complete-example-configlua)

---

## 1. Layout & Geometry

Define window spacing, rounded corner radius, and ribbon dimensions:

```lua
-- Inner gap between adjacent windows (in pixels)
Quire.config.gaps_in = 10

-- Outer margin gap around screen borders (in pixels)
Quire.config.gaps_out = 14

-- Corner rounding radius for borders in pixels (Direct2D overlay)
Quire.config.rounding = 8

-- Active and inactive border stroke width (in pixels)
Quire.config.border_size = 2

-- Default column width ratio relative to monitor width (0.1 to 1.0)
Quire.config.default_column_width = 1.0
```

---

## 2. Color Palette

Window borders and HUD elements are rendered via a Direct2D hardware overlay.  
Colors are defined using normalized RGBA tables with float values ranging from `0.0` to `1.0`:

```lua
-- { Red, Green, Blue, Alpha }
Quire.config.border_active   = { 0.54, 0.71, 0.98, 1.0 } -- Accent color for focused window
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.6 } -- Muted color for background clients
```

---

## 3. Spring Physics Engine

Viewport camera movement along horizontal ribbon and vertical workspaces is driven by sub-stepped numerical spring dynamics:

```lua
Quire.config.spring = {
    stiffness = 180, -- Spring tension: Higher values produce faster tracking snaps
    damping   = 22,  -- Resistance: Higher values reduce oscillation/bounciness
    mass      = 1.0  -- Virtual camera mass: Lower values feel lighter and snappier
}
```

---

## 4. Window Rules (Floating)

Specify client classes, window titles, or executable names that must bypass tiling and open as floating windows:

```lua
-- Add application identifiers to the float rules list
table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")
table.insert(Quire.window_rules.float, "NVIDIA GeForce Experience")
```

---

## 5. Keybindings & API

Keybindings are registered using `Quire.bind(chord, callback)`. 

### Available API Methods

| Function | Description |
| :--- | :--- |
| `Quire.focus_direction(dir)` | Shift focus (`"left"`, `"right"`, `"up"`, `"down"`). Scrolls ribbon if necessary. |
| `Quire.move_column(dir)` | Swap current column position (`"left"`, `"right"`). |
| `Quire.cycle_column_preset()` | Cycle active column width preset (`100%` -> `66%` -> `50%`). |
| `Quire.toggle_floating()` | Toggle floating state for current focused window. |
| `Quire.toggle_fullscreen()` | Toggle fullscreen state for active client. |
| `Quire.switch_workspace(id)` | Switch camera viewport to workspace `id` (1 through 9). |
| `Quire.move_to_workspace(id)` | Send focused client to workspace `id`. |
| `wm.close_window(hwnd)` | Gracefully close specified window handle. |
| `wm.spawn(executable)` | Launch an external program safely (sandboxed). |
| `launcher.toggle()` | Open/close the quick application launcher. |
| `launcher.commit()` | Execute currently selected item in the launcher. |

### Binding Examples

```lua
-- Focus navigation
Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

-- Move columns
Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)

-- Layout controls
Quire.bind("Alt+D", Quire.cycle_column_preset)
Quire.bind("Alt+V", Quire.toggle_floating)
Quire.bind("Alt+F", Quire.toggle_fullscreen)

-- Window management
Quire.bind("Alt+Q", function()
    if Quire.focused_window then
        wm.close_window(Quire.focused_window)
    end
end)

-- Workspaces (1 through 9)
for i = 1, 9 do
    Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
    Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
end
```

---

## 6. Built-in Launcher

Configure quick-launch applications accessed via `Alt+Space`:

```lua
Quire.apps = {
    { name = "Terminal",      path = "alacritty.exe" },
    { name = "File Explorer", path = "explorer.exe" },
    { name = "Code Editor",   path = "code.cmd" },
    { name = "Browser",       path = "firefox.exe" }
}

-- Launcher controls
Quire.bind("Alt+Space", launcher.toggle)
Quire.bind("Alt+Return", function()
    if Quire.launcher_active then
        launcher.commit()
    else
        wm.spawn("alacritty.exe")
    end
end)
Quire.bind("Alt+Escape", function()
    if Quire.launcher_active then launcher.toggle() end
end)
```

---

## 7. Process Spawning & Sandboxing

To ensure security against malicious scripts, QuireTWM runs Lua in an **isolated sandbox**. Standard arbitrary execution libraries (`os`, `io`, `debug`) are intentionally disabled.

To launch external processes safely from keybindings, use the built-in native API:

```lua
-- Correct:
Quire.bind("Alt+Return", function()
    wm.spawn("wt.exe")
end)

-- Incorrect (Disabled for security):
-- os.execute("start wt.exe")
```

---

## 8. Complete Example `config.lua`

```lua
-- QuireTWM Default Configuration
-- Path: %USERPROFILE%\.quire\config.lua

Quire.config.gaps_in = 8
Quire.config.gaps_out = 14
Quire.config.rounding = 8
Quire.config.border_size = 2
Quire.config.default_column_width = 1.0

-- Direct2D Accent Colors (RGBA float 0.0 - 1.0)
Quire.config.border_active = { 0.54, 0.71, 0.98, 1.0 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.6 }

-- Physics Solver
Quire.config.spring = {
    stiffness = 180,
    damping = 22,
    mass = 1.0
}

-- Floating Rules
table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")
table.insert(Quire.window_rules.float, "Steam")

-- Navigation
Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

-- Column & Layout Actions
Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)
Quire.bind("Alt+D", Quire.cycle_column_preset)
Quire.bind("Alt+V", Quire.toggle_floating)
Quire.bind("Alt+F", Quire.toggle_fullscreen)

-- Window Lifecycle
Quire.bind("Alt+Q", function()
    if Quire.focused_window then wm.close_window(Quire.focused_window) end
end)

-- Launcher & App Spawning
Quire.apps = {
    { name = "Terminal", path = "alacritty.exe" },
    { name = "Explorer", path = "explorer.exe" }
}

Quire.bind("Alt+Space", launcher.toggle)
Quire.bind("Alt+Return", function()
    if Quire.launcher_active then
        launcher.commit()
    else
        wm.spawn("alacritty.exe")
    end
end)
Quire.bind("Alt+Escape", function()
    if Quire.launcher_active then launcher.toggle() end
end)

-- Workspaces
for i = 1, 9 do
    Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
    Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
end
```
