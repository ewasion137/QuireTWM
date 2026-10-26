# QuireTWM

A scrollable ribbon tiling window manager for Windows 10 and 11. Built with C++ and Lua.

Inspired by scrollable Wayland compositors like Niri, QuireTWM replaces rigid grid splits with an infinite horizontal ribbon. The screen acts as a moving camera tracking your focused column, backed by sub-stepped numerical spring physics.

---

## Highlights

* **Scrollable Ribbon**: Windows sit in vertical columns along an unbounded horizontal axis. Focus smoothly glides the viewport.
* **Vertical Workspaces**: Workspaces stack on the Y-axis. Switching slides the viewport vertically without window teleport glitches.
* **Spring Dynamics**: Configurable mass, stiffness and damping drive every movement.
* **Direct2D Hardware Overlay**: Draws rounded active borders, HUD status and Alt-Tab cards at display refresh rate.
* **Zero Window Bleed**: Safely parks inactive workspace clients to avoid coordinate corruption.
* **Lua 5.4 Scripting**: Expressive configuration and keybindings via Sol2.
* **Built-in Alt-Tab & Launcher**: Fast overlay switcher and app menu out of the box.

---

## Architecture

1. **Layout Engine**: Windows live in dynamic columns. Each column can host multiple vertically stacked windows. The camera tracks focused elements along the horizontal plane.
2. **Event Pipeline**: Tracks system windows out-of-context via `SetWinEventHook` and handles keyboard shortcuts via low-level hooks. Frameless apps like Discord, VS Code and Spotify work correctly without child-window glitches.
3. **IPC Server**: Background worker thread listens on `\\.\pipe\quire` for fast external automation from PowerShell or shell scripts.

---

## Requirements

* Windows 10 or 11 (x64)
* Visual Studio 2022 (MSVC v143+) or C++ Build Tools
* CMake 3.20+
* Windows SDK (Direct2D, DirectWrite, DWM)

---

## Quickstart

```cmd
git clone https://github.com/ewasion137/QuireTWM.git
cd QuireTWM
cmake -B build -A x64
cmake --build build --config Release
```

The binary and scripts will land in `build/Release/`. Launch `QuireTWM.exe` to run.

---

## Configuration

Your config lives at `%USERPROFILE%\.quire\config.lua`. Changes reload automatically on save.

```lua
Quire.config.gaps_in = 8
Quire.config.gaps_out = 14
Quire.config.rounding = 10
Quire.config.border_size = 2
Quire.config.default_column_width = 1.0

-- Accent palette (RGBA normalized 0.0 to 1.0)
Quire.config.border_active = { 0.54, 0.71, 0.98, 1.0 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.6 }

-- Physics solver parameters
Quire.config.spring = {
    stiffness = 160,
    damping = 22,
    mass = 1.0
}

-- Floating rules
table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")

-- Navigation
Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

-- Column layout
Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)
Quire.bind("Alt+D", Quire.cycle_column_preset)

-- Window controls
Quire.bind("Alt+Q", function()
    if Quire.focused_window then wm.close_window(Quire.focused_window) end
end)
Quire.bind("Alt+V", Quire.toggle_floating)
Quire.bind("Alt+F", Quire.toggle_fullscreen)

-- Workspaces
for i = 1, 9 do
    Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
    Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
end
```

---

## Keybindings Reference

| Shortcut | Action |
| :--- | :--- |
| `Alt + H / L` | Focus left or right column |
| `Alt + K / J` | Focus upper or lower window in stack |
| `Alt + Shift + H / L` | Shift current column left or right |
| `Alt + D` | Cycle width preset (100% / 66% / 50%) |
| `Alt + V` | Toggle floating state |
| `Alt + F` | Toggle fullscreen view |
| `Alt + Q` | Close focused window |
| `Alt + Space` | Toggle launcher |
| `Alt + 1..9` | Switch to workspace |
| `Alt + Shift + 1..9` | Send window to workspace |

---

## IPC Interface

Send raw commands directly through the named pipe `\\.\pipe\quire`:

```powershell
# Send commands using PowerShell
.\quirectl.ps1 focus right
.\quirectl.ps1 workspace 2
.\quirectl.ps1 preset
.\quirectl.ps1 clients
```

Supported commands: `focus <dir>`, `move <dir>`, `preset`, `workspace <id>`, `movetoworkspace <id>`, `togglefloating`, `fullscreen`, `reload`, `close` and `clients`.
