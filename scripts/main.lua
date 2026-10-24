Quire = {}
HyprWin = Quire -- Страховка: если кто-то еще дернет HyprWin, краша не будет!

-- Дизайн-токены темы Quire
Quire.theme = {
    rounding = 10,
    border_size = 2,
    font_family = "Segoe UI Variable",
    bg_color = { 0.05, 0.05, 0.08, 0.92 },
    border_color = { 0.19, 0.20, 0.27, 0.60 },
    active_border_color = { 0.54, 0.71, 0.98, 1.00 },
    accent_color = { 0.54, 0.71, 0.98, 1.00 },
    text_color = { 0.90, 0.90, 0.95, 1.00 },
    text_dim = { 0.55, 0.55, 0.65, 0.80 },
}

-- ================= СОСТОЯНИЕ СИСТЕМЫ =================
Quire.current_workspace = 1
Quire.workspaces = {}         -- { [ws_id] = { columns = { {hwnd, ...}, ... } } }
Quire.focused_window = nil

Quire.floating_windows = {}   -- { [hwnd] = true }
Quire.floating_rects = {}     -- { [hwnd] = {x, y, w, h} }
Quire.fullscreen_windows = {} -- { [hwnd] = true }

Quire.column_widths = {}      -- { [col_key] = width_ratio }
Quire.window_targets = {}     -- { [hwnd] = { world_x, y, w, h } }
Quire.window_currents = {}    -- { [hwnd] = { x, y, w, h, vx, vy, vw, vh } }

Quire.window_rules = { float = {} }

-- Конфигурация по умолчанию
Quire.config = {
    gaps_in = 8,
    gaps_out = 14,
    default_column_width = 0.50,
    rounding = Quire.theme.rounding,
    border_size = Quire.theme.border_size,
    border_active = Quire.theme.active_border_color,
    border_inactive = Quire.theme.border_color,
    spring = { stiffness = 160, damping = 22, mass = 1.0 }
}

-- Подключение UI модулей ТЕПЕРЬ БЕЗОПАСНО
package.path = package.path .. ";./scripts/?.lua;./scripts/ui/?.lua"
local alttab = require("alttab")
local launcher = require("launcher")

-- Камера ленты
local camera_x = 0.0
local camera_target_x = 0.0
local camera_vx = 0.0

-- Вспомогательная функция проверки воркспейса
local function get_ws(ws_id)
    ws_id = ws_id or Quire.current_workspace
    if not Quire.workspaces[ws_id] then
        Quire.workspaces[ws_id] = { columns = {} }
    end
    return Quire.workspaces[ws_id]
end

-- Физика пружин (Spring Solver)
local function solve_spring(curr, vel, target, stiffness, damping, mass, dt)
    if dt <= 0 then return curr, vel end
    if math.abs(curr - target) < 0.5 and math.abs(vel) < 0.5 then
        return target, 0
    end
    dt = math.min(dt, 0.05)
    local steps = 4
    local sdt = dt / steps
    for _ = 1, steps do
        local force = -stiffness * (curr - target) - damping * vel
        vel = vel + (force / mass) * sdt
        curr = curr + vel * sdt
    end
    return curr, vel
end

-- Фильтр игнорируемых окон
local ignored_classes = {
    "WorkerW", "Progman", "Shell_TrayWnd", "QuireOverlay",
    "Chrome_ChildWin_Templ", "GhostWindow", "DesktopWindowXamlSource", 
    "MSCTFIME UI", "IME", "CicMarshalWnd", "TaskManagerWindow"
}

local function should_ignore(hwnd, title, class)
    if not title or title:match("^%s*$") then return true end
    for _, ic in ipairs(ignored_classes) do
        if class == ic then return true end
    end
    return false
end

function Quire.find_window_pos(hwnd, ws_id)
    local ws = get_ws(ws_id)
    for col_idx, col in ipairs(ws.columns) do
        for row_idx, w in ipairs(col) do
            if w == hwnd then return col_idx, row_idx, ws end
        end
    end
    return nil, nil, nil
end

-- ================= ПЕРЕСЧЕТ РАСКЛАДКИ (RETILE) =================
function Quire.retile()
    local sw, sh = wm.get_screen_size()
    local cfg = Quire.config
    local ws = get_ws(Quire.current_workspace)

    -- Если есть активное полноэкранное окно на этом воркспейсе
    local fs_win = nil
    for hwnd, _ in pairs(Quire.fullscreen_windows) do
        local col, _, win_ws = Quire.find_window_pos(hwnd)
        if win_ws == ws and wm.is_window_visible(hwnd) then
            fs_win = hwnd
            break
        end
    end

    if fs_win then
        Quire.window_targets[fs_win] = { world_x = 0, y = 0, w = sw, h = sh }
        camera_target_x = 0
        return
    end

    -- Очистка невалидных окон в колонках
    local cleaned_cols = {}
    for _, col in ipairs(ws.columns) do
        local valid_col = {}
        for _, hwnd in ipairs(col) do
            if wm.is_window_visible(hwnd) and not Quire.floating_windows[hwnd] then
                table.insert(valid_col, hwnd)
            end
        end
        if #valid_col > 0 then
            table.insert(cleaned_cols, valid_col)
        end
    end
    ws.columns = cleaned_cols

    local cur_x = cfg.gaps_out

    for col_idx, col in ipairs(ws.columns) do
        local col_key = Quire.current_workspace .. "_" .. col_idx
        local col_ratio = Quire.column_widths[col_key] or cfg.default_column_width
        local col_w = math.floor(sw * col_ratio)

        local n_rows = #col
        local total_gap_y = cfg.gaps_in * (n_rows - 1)
        local avail_h = sh - (cfg.gaps_out * 2) - total_gap_y
        local row_h = math.floor(avail_h / n_rows)

        local cur_y = cfg.gaps_out
        for row_idx, hwnd in ipairs(col) do
            local h = (row_idx == n_rows) and (sh - cfg.gaps_out - cur_y) or row_h
            Quire.window_targets[hwnd] = {
                world_x = cur_x,
                y = cur_y,
                w = col_w,
                h = h
            }
            cur_y = cur_y + h + cfg.gaps_in
        end
        cur_x = cur_x + col_w + cfg.gaps_in
    end

    -- Центрируем камеру на сфокусированном окне
    if Quire.focused_window and not Quire.floating_windows[Quire.focused_window] then
        local target = Quire.window_targets[Quire.focused_window]
        if target then
            camera_target_x = target.world_x - math.floor((sw - target.w) / 2)
        end
    end
end

-- ================= УПРАВЛЕНИЕ ОКНАМИ =================
local function apply_rules(hwnd, title, class)
    for _, pattern in ipairs(Quire.window_rules.float) do
        if class:match(pattern) or title:match(pattern) then
            Quire.floating_windows[hwnd] = true
            local x, y, w, h = wm.get_window_rect(hwnd)
            Quire.floating_rects[hwnd] = { x, y, w, h }
            return true
        end
    end
    return false
end

local function add_window(hwnd, title, class)
    if apply_rules(hwnd, title, class) then return end

    local col_idx, _, _ = Quire.find_window_pos(hwnd)
    if col_idx then return end

    local ws = get_ws(Quire.current_workspace)
    local active_col, _, _ = Quire.find_window_pos(Quire.focused_window)

    if active_col then
        table.insert(ws.columns, active_col + 1, { hwnd })
    else
        table.insert(ws.columns, { hwnd })
    end

    Quire.focused_window = hwnd
    Quire.retile()
end

local function remove_window(hwnd)
    Quire.floating_windows[hwnd] = nil
    Quire.floating_rects[hwnd] = nil
    Quire.fullscreen_windows[hwnd] = nil
    Quire.window_targets[hwnd] = nil
    Quire.window_currents[hwnd] = nil

    local col_idx, row_idx, ws = Quire.find_window_pos(hwnd)
    if not col_idx then return end

    table.remove(ws.columns[col_idx], row_idx)
    if #ws.columns[col_idx] == 0 then
        table.remove(ws.columns, col_idx)
    end

    if Quire.focused_window == hwnd then
        local next_col = ws.columns[col_idx] or ws.columns[col_idx - 1]
        Quire.focused_window = next_col and next_col[1] or nil
        if Quire.focused_window then
            wm.focus_window(Quire.focused_window)
        end
    end
    Quire.retile()
end

-- ================= ВОРКСПЕЙСЫ =================
function Quire.switch_workspace(target_ws)
    if target_ws == Quire.current_workspace then return end

    -- Прячем окна текущего воркспейса (сдвигаем далеко за экран, но безопасно)
    local cur_ws = get_ws(Quire.current_workspace)
    for _, col in ipairs(cur_ws.columns) do
        for _, hwnd in ipairs(col) do
            local curr = Quire.window_currents[hwnd]
            if curr then
                wm.move_window(hwnd, -3000, curr.y, curr.w, curr.h)
            end
        end
    end

    Quire.current_workspace = target_ws
    local new_ws = get_ws(target_ws)

    -- Фокусируем первое окно на новом воркспейсе
    if #new_ws.columns > 0 and #new_ws.columns[1] > 0 then
        Quire.focused_window = new_ws.columns[1][1]
        wm.focus_window(Quire.focused_window)
    else
        Quire.focused_window = nil
    end

    camera_x = 0
    camera_target_x = 0
    camera_vx = 0
    Quire.retile()
end

function Quire.move_to_workspace(target_ws)
    local focused = Quire.focused_window
    if not focused or Quire.floating_windows[focused] then return end

    local col_idx, row_idx, src_ws = Quire.find_window_pos(focused)
    if not col_idx then return end

    table.remove(src_ws.columns[col_idx], row_idx)
    if #src_ws.columns[col_idx] == 0 then
        table.remove(src_ws.columns, col_idx)
    end

    local dest_ws = get_ws(target_ws)
    table.insert(dest_ws.columns, { focused })

    -- Убираем его с экрана
    wm.move_window(focused, -3000, 100, 800, 600)
    Quire.window_targets[focused] = nil
    Quire.window_currents[focused] = nil

    Quire.retile()
end

-- ================= РЕСАЙЗ КОЛОНОК =================
function Quire.adjust_column_width(delta)
    local col_idx, _, _ = Quire.find_window_pos(Quire.focused_window)
    if not col_idx then return end

    local col_key = Quire.current_workspace .. "_" .. col_idx
    local cur_ratio = Quire.column_widths[col_key] or Quire.config.default_column_width
    local new_ratio = math.max(0.20, math.min(0.90, cur_ratio + delta))
    Quire.column_widths[col_key] = new_ratio
    Quire.retile()
end

-- ================= НАВИГАЦИЯ =================
function Quire.focus_direction(dir)
    local col_idx, row_idx, ws = Quire.find_window_pos(Quire.focused_window)
    if not col_idx then return end

    if dir == "left" and col_idx > 1 then
        local target = ws.columns[col_idx - 1][math.min(row_idx, #ws.columns[col_idx - 1])]
        wm.focus_window(target)
    elseif dir == "right" and col_idx < #ws.columns then
        local target = ws.columns[col_idx + 1][math.min(row_idx, #ws.columns[col_idx + 1])]
        wm.focus_window(target)
    elseif dir == "up" and row_idx > 1 then
        wm.focus_window(ws.columns[col_idx][row_idx - 1])
    elseif dir == "down" and row_idx < #ws.columns[col_idx] then
        wm.focus_window(ws.columns[col_idx][row_idx + 1])
    end
end

function Quire.move_column(dir)
    local col_idx, _, ws = Quire.find_window_pos(Quire.focused_window)
    if not col_idx then return end

    if dir == "left" and col_idx > 1 then
        ws.columns[col_idx], ws.columns[col_idx - 1] = ws.columns[col_idx - 1], ws.columns[col_idx]
        Quire.retile()
    elseif dir == "right" and col_idx < #ws.columns then
        ws.columns[col_idx], ws.columns[col_idx + 1] = ws.columns[col_idx + 1], ws.columns[col_idx]
        Quire.retile()
    end
end

function Quire.toggle_floating()
    local focused = Quire.focused_window
    if not focused then return end

    if Quire.floating_windows[focused] then
        Quire.floating_windows[focused] = nil
        Quire.floating_rects[focused] = nil
        add_window(focused, wm.get_window_title(focused), wm.get_class_name(focused))
    else
        remove_window(focused)
        Quire.floating_windows[focused] = true
        local x, y, w, h = wm.get_window_rect(focused)
        Quire.floating_rects[focused] = { x, y, w, h }
    end
    Quire.retile()
end

function Quire.toggle_fullscreen()
    local focused = Quire.focused_window
    if not focused then return end

    if Quire.fullscreen_windows[focused] then
        Quire.fullscreen_windows[focused] = nil
    else
        Quire.fullscreen_windows[focused] = true
    end
    Quire.retile()
end

-- ================= СИСТЕМНЫЕ СОБЫТИЯ =================
Quire.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then return end

    if event_type == 0x0003 then -- Фокус
        Quire.focused_window = hwnd
        local col_idx, _, _ = Quire.find_window_pos(hwnd)
        if not col_idx and not Quire.floating_windows[hwnd] and wm.is_toplevel(hwnd) then
            add_window(hwnd, title, class)
        else
            Quire.retile()
        end
        return
    end

    if event_type == 0x8002 or event_type == 0x0017 then -- Создание
        if wm.is_toplevel(hwnd) then
            add_window(hwnd, title, class)
        end
        return
    end

    if event_type == 0x8001 or event_type == 0x0016 then -- Уничтожение / минимизация
        remove_window(hwnd)
        return
    end
end

-- ================= КАДР АНИМАЦИИ И РЕНДЕР =================
local last_time = os.clock()

Quire.on_render_overlay = function()
    local now = os.clock()
    local dt = math.max(0.001, math.min(now - last_time, 0.033))
    last_time = now

    local cfg = Quire.config
    local sp = cfg.spring
    local sw, sh = wm.get_screen_size()

    -- 1. Движение камеры
    camera_x, camera_vx = solve_spring(camera_x, camera_vx, camera_target_x, sp.stiffness, sp.damping, sp.mass, dt)

    -- 2. Обновление физических окон ленты
    local ws = get_ws(Quire.current_workspace)
    for _, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col) do
            local target = Quire.window_targets[hwnd]
            if target then
                local screen_target_x = target.world_x - math.floor(camera_x)
                local curr = Quire.window_currents[hwnd]

                if not curr then
                    curr = { x = screen_target_x, y = target.y, w = target.w, h = target.h, vx = 0, vy = 0, vw = 0, vh = 0 }
                    Quire.window_currents[hwnd] = curr
                    wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                else
                    curr.x, curr.vx = solve_spring(curr.x, curr.vx, screen_target_x, sp.stiffness, sp.damping, sp.mass, dt)
                    curr.y, curr.vy = solve_spring(curr.y, curr.vy, target.y, sp.stiffness, sp.damping, sp.mass, dt)
                    curr.w, curr.vw = solve_spring(curr.w, curr.vw, target.w, sp.stiffness, sp.damping, sp.mass, dt)
                    curr.h, curr.vh = solve_spring(curr.h, curr.vh, target.h, sp.stiffness, sp.damping, sp.mass, dt)

                    -- Двигаем окно только если оно в зоне видимости (+/- буфер)
                    if curr.x > -curr.w - 100 and curr.x < sw + 100 then
                        wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                    end
                end
            end
        end
    end

    -- 3. Отрисовка рамок активных/неактивных окон
    for _, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col) do
            local curr = Quire.window_currents[hwnd]
            if curr and curr.x > -curr.w and curr.x < sw then
                local is_active = (hwnd == Quire.focused_window)
                local col_color = is_active and cfg.border_active or cfg.border_inactive
                ui.draw_rounded_rect(curr.x, curr.y, curr.w, curr.h, cfg.rounding, col_color[1], col_color[2], col_color[3], col_color[4], cfg.border_size)
            end
        end
    end

    -- 4. Отрисовка UI модалок (Alt-Tab и Launcher)
    alttab.draw()
    launcher.draw(1.0)
end

-- ================= ОБРАБОТЧИКИ C++ СОБЫТИЙ =================
Quire.on_alttab_action = function(action_type)
    alttab.action(action_type)
end

Quire.on_ipc_request = function(req)
    if not req or req == "" then return "ERROR: Empty command" end
    local parts = {}
    for part in req:gmatch("%S+") do table.insert(parts, part) end
    local cmd = parts[1]:lower()

    if cmd == "focus" and parts[2] then
        Quire.focus_direction(parts[2]:lower())
        return "OK"
    elseif cmd == "move" and parts[2] then
        Quire.move_column(parts[2]:lower())
        return "OK"
    elseif cmd == "workspace" and parts[2] then
        Quire.switch_workspace(tonumber(parts[2]) or 1)
        return "OK"
    elseif cmd == "movetoworkspace" and parts[2] then
        Quire.move_to_workspace(tonumber(parts[2]) or 1)
        return "OK"
    elseif cmd == "togglefloating" then
        Quire.toggle_floating()
        return "OK"
    elseif cmd == "fullscreen" then
        Quire.toggle_fullscreen()
        return "OK"
    elseif cmd == "close" then
        if Quire.focused_window then wm.close_window(Quire.focused_window) end
        return "OK"
    elseif cmd == "clients" then
        local out = {}
        for ws_id, ws in pairs(Quire.workspaces) do
            for c_i, col in ipairs(ws.columns) do
                for r_i, hwnd in ipairs(col) do
                    table.insert(out, string.format("WS:%d Col:%d Row:%d [0x%X] %s", ws_id, c_i, r_i, hwnd, wm.get_window_title(hwnd)))
                end
            end
        end
        return #out > 0 and table.concat(out, "\n") or "No tiled clients"
    end
    return "ERROR: Unknown command " .. cmd
end

-- ================= БИНДИНГИ ХОТКЕЕВ =================
Quire.hotkeys = {}
local hotkey_counter = 1

local function parse_combo(combo)
    local parts = {}
    for part in string.gmatch(combo, "[^+%s]+") do table.insert(parts, part:upper()) end
    local mod, vk = 0, 0
    for i = 1, #parts - 1 do
        local p = parts[i]
        if p == "SUPER" or p == "WIN" then mod = mod + 0x0008
        elseif p == "SHIFT" then mod = mod + 0x0004
        elseif p == "CTRL" or p == "CONTROL" then mod = mod + 0x0002
        elseif p == "ALT" then mod = mod + 0x0001
        end
    end
    local key = parts[#parts]
    if #key == 1 then
        vk = string.byte(key)
    else
        local special = {
            ["LEFT"] = 0x25, ["UP"] = 0x26, ["RIGHT"] = 0x27, ["DOWN"] = 0x28,
            ["RETURN"] = 0x0D, ["ENTER"] = 0x0D, ["SPACE"] = 0x20,
            ["TAB"] = 0x09, ["ESCAPE"] = 0x1B, ["MINUS"] = 0xBD, ["EQUAL"] = 0xBB
        }
        vk = special[key] or 0
    end
    return mod, vk
end

function Quire.bind(combo, callback)
    local mod, vk = parse_combo(combo)
    if vk == 0 then return end
    local id = hotkey_counter
    hotkey_counter = hotkey_counter + 1
    Quire.hotkeys[id] = callback
    wm.register_hotkey(id, mod, vk)
end

Quire.on_hotkey = function(id)
    if Quire.hotkeys[id] then Quire.hotkeys[id]() end
end

-- ================= ИНИЦИАЛИЗАЦИЯ И ДЕФОЛТНЫЙ СТАРТ =================
-- Захват уже открытых окон в воркспейс 1
local existing = wm.enumerate_windows()
local ws1 = get_ws(1)
for _, hwnd in ipairs(existing) do
    local title = wm.get_window_title(hwnd)
    local class = wm.get_class_name(hwnd)
    if not should_ignore(hwnd, title, class) then
        table.insert(ws1.columns, { hwnd })
    end
end
if #ws1.columns > 0 then
    Quire.focused_window = ws1.columns[1][1]
end

-- Загрузка конфига
local config_path = wm.get_config_path()
if not pcall(dofile, config_path) then
    log("Config not found/error. Registering default Quire binds...")

    -- Фокус (HJKL)
    Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
    Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
    Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
    Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

    -- Перемещение колонок
    Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
    Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)

    -- Ресайз активной колонки (Шире / Уже)
    Quire.bind("Alt+Minus", function() Quire.adjust_column_width(-0.05) end)
    Quire.bind("Alt+Equal", function() Quire.adjust_column_width(0.05) end)

    -- Управление окном
    Quire.bind("Alt+Q", function() if Quire.focused_window then wm.close_window(Quire.focused_window) end end)
    Quire.bind("Alt+F", Quire.toggle_fullscreen)
    Quire.bind("Alt+V", Quire.toggle_floating)

    -- Лаунчер
    Quire.bind("Alt+D", launcher.toggle)
    Quire.bind("Alt+Return", launcher.commit)

    -- Воркспейсы (Alt + 1..9 и Alt + Shift + 1..9)
    for i = 1, 9 do
        Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
        Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
    end
end

Quire.retile()