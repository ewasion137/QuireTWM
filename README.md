# QuireTWM

A high-performance, scrollable-ribbon tiling window manager for Windows 10/11 built with C++20, Direct2D, and Lua 5.4.

Inspired by modern scrollable Wayland compositors (like Niri), QuireTWM abandons cramped binary tree subdivisions in favor of an **infinite horizontal ribbon** with dynamic columns, vertical sliding workspaces, and smooth sub-stepped spring physics.

---

## Key Features

* **Infinite Scrollable Ribbon**: Windows are laid out linearly in columns along an unbounded horizontal axis. The screen acts as a fluid viewport (camera) tracking the active column.
* **Vertical Workspace Model**: Workspaces are stacked vertically (Y-axis). Switching workspaces smoothly slides ribbons along the vertical plane with zero window-teleport artifacts.
* **Spring Dynamics**: Smooth, physics-based camera easing and window transitions with customizable stiffness, damping, and mass.
* **Direct2D Hardware-Accelerated Overlay**: Zero-latency layered window rendering rounded borders, active window accents, and integrated task switcher (Alt+Tab) at native display refresh rates.
* **Robust Win32 & Frameless Electron Support**: Native heuristics accurately track standard applications as well as modern frameless Electron/Chromium apps (VS Code, Discord, Spotify, custom player frontends) without false child-window destructions.
* **Zero Window Bleed**: Inactive workspace windows are safely parked without coordinate corruption, preventing stuck opacity or off-screen window loss during abrupt termination.
* **Native Lua 5.4 Scriptability**: Expressive, Turing-complete configuration using pure Lua via `sol2`.

---

## Architecture

### 1. Layout & Viewport Engine
Instead of recursive Binary Space Partitioning (BSP), QuireTWM arranges windows into an array of columns:
$$\text{col}_w = (\text{ratio} \ge 0.99) \ ? \ \text{avail}_w : \lfloor (\text{avail}_w - \text{gaps}_{\text{in}}) \times \text{ratio} \rfloor$$
Each column holds one or more vertically stacked windows. The camera position along the X-axis is bounded and centered over the focused column using sub-stepped numerical spring solvers.

### 2. Event Pipeline & Window Tracking
* Window events are monitored out-of-context via `SetWinEventHook` without DLL injection:
  * `EVENT_SYSTEM_FOREGROUND` (Focus redirection and auto-workspace jump)
  * `EVENT_OBJECT_CREATE` / `EVENT_OBJECT_DESTROY` / `EVENT_OBJECT_NAMECHANGE`
  * `EVENT_SYSTEM_MINIMIZESTART` / `EVENT_SYSTEM_MINIMIZEEND`
* Low-level keyboard hook (`WH_KEYBOARD_LL`) provides instantaneous capture of `Alt+Tab` events directly dispatched to the Lua overlay engine.
* Top-level filtering inspects window styles (`WS_POPUP`, `WS_CAPTION`, `WS_EX_APPWINDOW`) while strictly rejecting child controls to maintain layout stability across tab and tooltip operations.

### 3. IPC Architecture
* Dedicated background worker thread hosts a duplex Named Pipe at `\\.\pipe\quire`.
* Requests are synchronized with the UI thread via `WM_QUIRE_IPC` to prevent concurrent access to the Lua runtime.

---

## Prerequisites

* Windows 10/11 x86_64
* MSVC v143+ (Visual Studio 2022 or Build Tools)
* CMake 3.20+
* Windows SDK (Direct2D, DirectWrite, DWM APIs)

---

## Building

```cmd
git clone https://github.com/ewasion137/QuireTWM.git
cd QuireTWM
cmake -B build -A x64
cmake --build build --config Release
```

The compiled executable and default runtime scripts will be output to `build/Release/`.

---

## Configuration

Configuration is loaded from `%USERPROFILE%\.quire\config.lua`.

```lua
-- Layout & Grid Settings
Quire.config.gaps_in = 8
Quire.config.gaps_out = 14
Quire.config.rounding = 10
Quire.config.border_size = 2
Quire.config.default_column_width = 1.0 -- Open windows at 100% width

-- Theme Palette (RGBA normalized 0.0 - 1.0)
Quire.config.border_active = { 0.54, 0.71, 0.98, 1.0 }
Quire.config.border_inactive = { 0.19, 0.20, 0.27, 0.6 }

-- Spring Animation Physics
Quire.config.spring = {
    stiffness = 160,
    damping = 22,
    mass = 1.0
}

-- Window Rules (Force floating state)
table.insert(Quire.window_rules.float, "CalculatorApp")
table.insert(Quire.window_rules.float, "TaskManagerWindow")

-- Keybindings
Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

-- Column Management
Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)
Quire.bind("Alt+D", Quire.cycle_column_preset) -- Cycles: 100% -> 66% -> 50%

-- Window State
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

## IPC Interface

The Named Pipe endpoint at `\\.\pipe\quire` accepts plain-text commands.

### Supported Dispatchers

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `focus` | `left` \| `right` \| `up` \| `down` | Move focus directionally across the ribbon or stack |
| `move` | `left` \| `right` | Reorder active column within the current workspace |
| `preset` | — | Cycle column width presets (100% / 66% / 50%) |
| `workspace` | `<1-9>` | Switch to targeted vertical workspace |
| `movetoworkspace` | `<1-9>` | Transfer active window to targeted workspace |
| `togglefloating` | — | Detach active client into centered floating mode |
| `fullscreen` | — | Toggle fullscreen view over active workspace |
| `close` | — | Terminate active client |
| `clients` | — | List all managed windows, workspaces, and column coordinates |

### Control via PowerShell

Use `quirectl.ps1` to send commands directly to the running instance:

```powershell
.\quirectl.ps1 focus right
.\quirectl.ps1 workspace 2
.\quirectl.ps1 preset
.\quirectl.ps1 clients
```