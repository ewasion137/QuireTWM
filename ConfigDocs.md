
### 1. Фикс темной обводки поверх Проводника

**Почему обводка вылезала поверх Проводника:**
Окно оверлея `QuireOverlay` создается с системным флагом `WS_EX_TOPMOST` (поверх всех окон), чтобы рисовать рамки на экране. Проводник и Real при открытии во флоате оставались обычными окнами (`HWND_NOTOPMOST`). Из-за этого оверлей физически рисовался поверх тела Проводника, разрезая его рамками фоновых окон.

**Решение:**
Плавающие окна должны получать флаг `HWND_TOPMOST`, чтобы парить **над** оверлеем с рамками фонового тайлинга. А при возвращении в тайлинг — сбрасывать его в `HWND_NOTOPMOST`.

В `scripts/main.lua` замени две функции:

#### В `apply_rules`:
```lua
local function apply_rules(hwnd, title, class)
    local proc = (wm.get_process_name and wm.get_process_name(hwnd) or ""):lower()
    local low_title = (title or ""):lower()
    local low_class = (class or ""):lower()

    for _, pattern in ipairs(Quire.window_rules.float) do
        local p = pattern:lower()
        if proc:find(p, 1, true) or low_title:find(p, 1, true) or low_class:find(p, 1, true) then
            Quire.floating_windows[hwnd] = true

            local wx, wy, ww, wh = wm.get_work_area()
            local fw = math.floor(ww * 0.60)
            local fh = math.floor(wh * 0.70)
            local fx = wx + math.floor((ww - fw) / 2)
            local fy = wy + math.floor((wh - fh) / 2)

            Quire.floating_rects[hwnd] = { fx, fy, fw, fh }
            wm.move_window(hwnd, fx, fy, fw, fh)
            -- Поднимаем флоат поверх оверлея рамок
            SetWindowPos and SetWindowPos(hwnd, -1, 0, 0, 0, 0, 0x0001 | 0x0002)
            return true
        end
    end
    return false
end
```

#### В `Quire.toggle_floating`:
```lua
function Quire.toggle_floating()
    local focused = Quire.focused_window
    if not focused then return end

    local wx, wy, ww, wh = wm.get_work_area()

    if Quire.floating_windows[focused] then
        Quire.floating_windows[focused] = nil
        Quire.floating_rects[focused] = nil
        local ws = get_ws(Quire.current_workspace)
        table.insert(ws.columns, { width = Quire.config.default_column_width, windows = { focused } })
        Quire.retile()
    else
        local col_idx, row_idx, ws = Quire.find_window_pos(focused)
        if col_idx then
            table.remove(ws.columns[col_idx].windows, row_idx)
            if #ws.columns[col_idx].windows == 0 then
                table.remove(ws.columns, col_idx)
            end
        end

        Quire.floating_windows[focused] = true
        Quire.window_targets[focused] = nil
        Quire.window_currents[focused] = nil

        local fw = math.floor(ww * 0.60)
        local fh = math.floor(wh * 0.70)
        local fx = wx + math.floor((ww - fw) / 2)
        local fy = wy + math.floor((wh - fh) / 2)

        Quire.floating_rects[focused] = { fx, fy, fw, fh }
        wm.move_window(focused, fx, fy, fw, fh)
    end
    trigger_hud()
end
```

И в `main.cpp` экспортируй установку topmost для флоата, либо в `wm.move_window`:
В `main.cpp` в `wm.move_window`:
```cpp
        wm.set_function("move_window", [](size_t hwnd, double x, double y, double w, double h) {
            HWND handle = reinterpret_cast<HWND>(hwnd);
            if (IsZoomed(handle)) ShowWindow(handle, SW_RESTORE);

            // Если окно во флоате — держим его TOPMOST поверх оверлея
            HWND insertAfter = HWND_NOTOPMOST;
            if (g_lua) {
                sol::protected_function is_f = (*g_lua)["Quire"]["is_floating"];
                if (is_f.valid() && is_f(hwnd).get<bool>()) {
                    insertAfter = HWND_TOPMOST;
# QuireTWM Configuration Reference

The configuration file is located at:
```
%USERPROFILE%\.quire\config.lua
```
Changes saved to this file are automatically hot-reloaded at runtime without restarting the window manager.

---

## 1. Grid & Dimensions (`Quire.config`)

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `gaps_in` | `number` | `8` | Inner margin between tiled columns and stacked rows (pixels). |
| `gaps_out` | `number` | `14` | Outer margin between the ribbon edges and the screen boundaries. |
| `rounding` | `number` | `10` | Corner radius for Direct2D window borders and modal dialogs. |
| `border_size` | `number` | `2` | Stroke thickness for window outline borders. |
| `default_column_width` | `number` | `1.0` | Initial width ratio for newly opened windows (`1.0` = 100% work area). |

---

## 2. Appearance & Colors

Colors are defined as normalized RGBA arrays `[0.0 - 1.0]`:

```lua
Quire.config.border_active = { 0.73, 0.46, 0.98, 1.0 }   -- Focused window border (Tokyo Night Purple)
Quire.config.border_inactive = { 0.16, 0.17, 0.24, 0.6 } -- Inactive window border
```

---

## 3. Spring Physics Engine (`Quire.config.spring`)

Controls the numerical spring dynamics for viewport panning, column animations, and workspace slides:

```lua
Quire.config.spring = {
    stiffness = 260, -- Spring tension. Higher values result in snappier, faster movement.
    damping = 26,    -- Resistance to oscillation. Lower values produce bouncier motion.
    mass = 1.0       -- Window inertia. Minimum value clamped to 0.05.
}
```

---

## 4. Custom Work Area & Struts (`Quire.config.padding`)

Defines additional manual offsets to accommodate floating status bars (like YASB or Windhawk Docks):

```lua
Quire.config.padding = {
    top = 0,     -- Additional top padding (e.g., 36 for a floating top status bar)
    bottom = 0,  -- Additional bottom padding
    left = 0,
    right = 0
}
```

---

## 5. Window Rules (`Quire.window_rules.float`)

Matches windows that must bypass the ribbon and open as floating modals. Case-insensitive substring matching against process executable names (`.exe`), window titles, and Win32 class names:

```lua
table.insert(Quire.window_rules.float, "explorer.exe")
table.insert(Quire.window_rules.float, "Taskmgr")
table.insert(Quire.window_rules.float, "CalculatorApp")
```

---

## 6. Keybindings API (`Quire.bind`)

```lua
Quire.bind("<Modifiers>+<Key>", callback)
```

Modifiers: `Alt`, `Shift`, `Ctrl`, `Super` (or `Win`).

### Available Dispatchers
* `Quire.focus_direction("left" | "right" | "up" | "down")`
* `Quire.move_column("left" | "right")`
* `Quire.consume_into_column("left" | "right")`
* `Quire.eject_from_column()`
* `Quire.move_window_stack("up" | "down")`
* `Quire.cycle_column_preset()`
* `Quire.adjust_column_width(delta)`
* `Quire.switch_workspace(index)`
* `Quire.move_to_workspace(index)`
* `Quire.toggle_floating()`
* `Quire.toggle_fullscreen()`
* `wm.close_window(hwnd)`
* `wm.spawn(command)`
