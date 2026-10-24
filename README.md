# HyprWin

Dynamic tiling window manager for Windows made with C++ and Lua. Made to support original Hyprland configs as much as it can. In active development

---

## Architecture

### 1. Window Management
* Layout positioning queries `DWMWA_EXTENDED_FRAME_BOUNDS` through `DwmGetWindowAttribute` to negate invisible DWM drop shadows and show exact visible boundaries.
* Off-workspace applications are hidden using coordinate offsets (`-32000, -32000`) and checked `DWMWA_CLOAKED` to filter out UWP background and virtual desktop stubs.

### 2. Events
* Global hooks (`SetWinEventHook`) capture events without DLL injection:
  * `EVENT_OBJECT_CREATE` / `EVENT_OBJECT_DESTROY`
  * `EVENT_SYSTEM_FOREGROUND`
  * `EVENT_SYSTEM_MINIMIZESTART` / `EVENT_SYSTEM_MINIMIZEEND`
* A hook (`WH_KEYBOARD_LL`) catches `Alt+Tab` key and switches state updates directly to the Lua task switcher in the HyprWin.

### 3. States & Animations
* Lua 5.4 through sol2.
* Uses Binary Space Partitioning (BSP) and Master layouts.

### 4. IPC Architecture
* Has a dedicated worker thread running a Named Pipe endpoint at `\\.\pipe\hyprwin`.
* Requests are synchronized throuth the `WM_HYPRWIN_IPC` to prevent concurrent access to Lua engine.

---

## Dependencies

* Windows 10/11 x86_64
* MSVC v143+
* CMake 3.20+
* Windows SDK

---

## Build

```cmd
git clone https://github.com/ewasion137/HyprWin.git
cd HyprWin
cmake -B build -A x64
cmake --build build --config Release
```

Output and the compiled application will lay in `build/Release/`.

---

## Configuration

Configuration is loaded from `%USERPROFILE%\.hyprwin\hyprland.lua`. If does'nt, a template is created on initial launch.

```lua
hl.config({
    general = {
        gaps_in = 6,
        gaps_out = 12,
        border_size = 2,
        layout = "bsp",
        col = {
            active_border = "rgba(7aa2f7ff)",
            inactive_border = "rgba(1a1b26aa)"
        }
    },
    decoration = {
        rounding = 8
    },
    animations = {
        enabled = true
    }
})

-- Keybindings: Modifier + Key
hl.bind("ALT + RETURN", hl.dsp.exec_cmd("cmd.exe"))
hl.bind("ALT + Q",      hl.dsp.window.close())
hl.bind("ALT + SPACE",  hl.dsp.window.float())

-- Workspaces
for i = 1, 9 do
    hl.bind("ALT + " .. i, hl.dsp.workspace(tostring(i)))
    hl.bind("ALT + SHIFT + " .. i, hl.dsp.movetoworkspace(tostring(i)))
end
```

---

## IPC

The Named Pipe server accepts newline-delimited ASCII commands at `\\.\pipe\hyprwin`.

### Dispatchers

| Command | Arguments | Description |
| :--- | :--- | :--- |
| `dispatch workspace` | `<index>` | Focus specified workspace |
| `dispatch movetoworkspace` | `<index>` | Move active window to workspace |
| `dispatch exec` | `<path>` | Execute process |
| `dispatch togglefloating` | — | Toggle floating state for active window |
| `dispatch killactive` | — | Kill active window |
| `dispatch movefocus` | `left` \| `right` \| `up` \| `down` | Shift focus directionally |
| `dispatch swapwindow` | `left` \| `right` \| `up` \| `down` | Swap window positions |

### System Queries

| Command | Description | Response Format |
| :--- | :--- | :--- |
| `activewindow` | Retreive handle and title of focused client | `HWND: 0x... \n Class: ... \n Title: ...` |
| `clients` | Enumerate all tracked windows across layouts | List of registered window descriptors |
| `setprop` | `<HWND/activewindow> opacity <0.1-1.0>` | Mutate Win32 alpha layered attributes |

### Usage with PowerShell

```powershell
.\hyprctl.ps1 "dispatch workspace 2"
.\hyprctl.ps1 "activewindow"
```

---

*HyprWin is in active development and is a project build with help of AI, it's raw and buggy, ill be happy for you to write in the issues your suggestions to improve, found bugs or even contribute to it! I allow AI to contribute to the project, as is the project is made using AI, but make sure all works and all tested and nothing else breaks.*


<img width="800" height="450" alt="0928-ezgif com-video-to-gif-converter" src="https://github.com/user-attachments/assets/eb15378e-6080-4eea-9e3e-4b3a1f0a3a8e" />
