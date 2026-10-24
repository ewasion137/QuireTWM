Quire = {}
HyprWin = Quire

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

Quire.current_workspace = 1
Quire.animating_ws = nil
Quire.anim_direction = 1
Quire.workspaces = {}
Quire.window_ws = {}
Quire.focused_window = nil

Quire.floating_windows = {}
Quire.floating_rects = {}
Quire.fullscreen_windows = {}

Quire.window_targets = {}
Quire.window_currents = {}
Quire.window_rules = { float = {} }

Quire.config = {
    gaps_in = 8,
    gaps_out = 14,
    default_column_width = 1.0,
    rounding = Quire.theme.rounding,
    border_size = Quire.theme.border_size,
    border_active = Quire.theme.active_border_color,
    border_inactive = Quire.theme.border_color,
    spring = { stiffness = 160, damping = 22, mass = 1.0 }
}

package.path = package.path .. ";./scripts/?.lua;./scripts/ui/?.lua"
local alttab = require("alttab")
local launcher = require("launcher")

local camera_x = 0.0
local camera_y = 0.0
local camera_target_x = 0.0
local camera_target_y = 0.0
local camera_vx = 0.0
local camera_vy = 0.0

local function get_ws(ws_id)
    ws_id = ws_id or Quire.current_workspace
    if not Quire.workspaces[ws_id] then
        Quire.workspaces[ws_id] = { columns = {} }
    end
    return Quire.workspaces[ws_id]
end

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

function Quire.find_window_pos(hwnd)
    for ws_id, ws in pairs(Quire.workspaces) do
        for col_idx, col in ipairs(ws.columns) do
            for row_idx, w in ipairs(col.windows) do
                if w == hwnd then return col_idx, row_idx, ws, ws_id end
            end
        end
    end
    return nil, nil, nil, nil
end

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

local function layout_columns(ws_id, sw, sh, cfg, avail_w)
    local ws = get_ws(ws_id)
    local cur_x = cfg.gaps_out

    for _, col in ipairs(ws.columns) do
        local col_w = (col.width >= 0.99) and avail_w or math.floor((avail_w - cfg.gaps_in) * col.width)
        local n_rows = #col.windows
        local total_gap_y = cfg.gaps_in * (n_rows - 1)
        local avail_h = sh - (cfg.gaps_out * 2) - total_gap_y
        local row_h = math.floor(avail_h / n_rows)

        local cur_y = cfg.gaps_out
        for row_idx, hwnd in ipairs(col.windows) do
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
    return cur_x
end

function Quire.retile()
    local sw, sh = wm.get_screen_size()
    local cfg = Quire.config
    local ws = get_ws(Quire.current_workspace)

    local fs_win = nil
    for hwnd, _ in pairs(Quire.fullscreen_windows) do
        local _, _, win_ws, _ = Quire.find_window_pos(hwnd)
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

    local cleaned_cols = {}
    for _, col in ipairs(ws.columns) do
        local valid_wins = {}
        for _, hwnd in ipairs(col.windows) do
            if wm.is_window_visible(hwnd) and not Quire.floating_windows[hwnd] then
                table.insert(valid_wins, hwnd)
            end
        end
        if #valid_wins > 0 then
            col.windows = valid_wins
            table.insert(cleaned_cols, col)
        end
    end
    ws.columns = cleaned_cols

    local avail_w = sw - (cfg.gaps_out * 2)

    if Quire.animating_ws then
        layout_columns(Quire.animating_ws, sw, sh, cfg, avail_w)
    end
    local total_w = layout_columns(Quire.current_workspace, sw, sh, cfg, avail_w)

    if Quire.focused_window and not Quire.floating_windows[Quire.focused_window] then
        local target = Quire.window_targets[Quire.focused_window]
        if target then
            camera_target_x = target.world_x - math.floor((sw - target.w) / 2)
        end
    end

    local max_cam_x = math.max(0, total_w - cfg.gaps_in + cfg.gaps_out - sw)
    camera_target_x = math.max(0, math.min(max_cam_x, camera_target_x))
end

local function add_window(hwnd, title, class)
    if Quire.floating_windows[hwnd] then return end
    if apply_rules(hwnd, title, class) then return end

    local col_idx, _, _, existing_ws = Quire.find_window_pos(hwnd)
    if col_idx then
        if existing_ws ~= Quire.current_workspace then
            Quire.switch_workspace(existing_ws)
        end
        return
    end

    local ws = get_ws(Quire.current_workspace)
    local active_col, _, _, _ = Quire.find_window_pos(Quire.focused_window)

    local new_col = {
        width = Quire.config.default_column_width,
        windows = { hwnd }
    }

    if active_col and active_col <= #ws.columns then
        table.insert(ws.columns, active_col + 1, new_col)
    else
        table.insert(ws.columns, new_col)
    end

    Quire.window_ws[hwnd] = Quire.current_workspace
    Quire.focused_window = hwnd
    Quire.retile()
end

local function remove_window(hwnd, is_destroy)
    if is_destroy then
        Quire.floating_windows[hwnd] = nil
        Quire.floating_rects[hwnd] = nil
    end

    Quire.fullscreen_windows[hwnd] = nil
    Quire.window_targets[hwnd] = nil
    Quire.window_currents[hwnd] = nil
    Quire.window_ws[hwnd] = nil

    local col_idx, row_idx, ws, _ = Quire.find_window_pos(hwnd)
    if not col_idx then return end

    table.remove(ws.columns[col_idx].windows, row_idx)
    if #ws.columns[col_idx].windows == 0 then
        table.remove(ws.columns, col_idx)
    end

    if Quire.focused_window == hwnd then
        local target_col = ws.columns[col_idx] or ws.columns[col_idx - 1]
        if target_col and #target_col.windows > 0 then
            Quire.focused_window = target_col.windows[1]
            wm.focus_window(Quire.focused_window)
        else
            Quire.focused_window = nil
        end
    end

    Quire.retile()
end

function Quire.switch_workspace(target_ws)
    if target_ws == Quire.current_workspace then return end

    local old_ws = Quire.current_workspace
    local sw, sh = wm.get_screen_size()
    local direction = (target_ws > old_ws) and 1 or -1

    Quire.animating_ws = old_ws
    Quire.anim_direction = direction
    Quire.current_workspace = target_ws
    Quire.suppress_switch_until = os.clock() + 1.2

    camera_y = direction * sh
    camera_vy = 0

    local new_ws = get_ws(target_ws)
    if #new_ws.columns > 0 and #new_ws.columns[1].windows > 0 then
        Quire.focused_window = new_ws.columns[1].windows[1]
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

    local col_idx, row_idx, src_ws, _ = Quire.find_window_pos(focused)
    if not col_idx then return end

    local col = src_ws.columns[col_idx]
    table.remove(col.windows, row_idx)
    local col_w = col.width
    if #col.windows == 0 then
        table.remove(src_ws.columns, col_idx)
    end

    local dest_ws = get_ws(target_ws)
    table.insert(dest_ws.columns, { width = col_w, windows = { focused } })
    Quire.window_ws[focused] = target_ws

    wm.move_window(focused, -20000, 100, 800, 600)
    Quire.window_targets[focused] = nil
    Quire.window_currents[focused] = nil

    local next_col = src_ws.columns[col_idx] or src_ws.columns[col_idx - 1]
    Quire.focused_window = (next_col and #next_col.windows > 0) and next_col.windows[1] or nil
    if Quire.focused_window then
        wm.focus_window(Quire.focused_window)
    end

    Quire.retile()
end

function Quire.adjust_column_width(delta)
    local col_idx, _, ws, _ = Quire.find_window_pos(Quire.focused_window)
    if not col_idx then return end
    local col = ws.columns[col_idx]
    col.width = math.max(0.20, math.min(1.0, col.width + delta))
    Quire.retile()
end

local width_presets = { 1.0, 0.666, 0.50 }

function Quire.cycle_column_preset()
    local col_idx, _, ws, _ = Quire.find_window_pos(Quire.focused_window)
    if not col_idx then return end
    local col = ws.columns[col_idx]

    local next_ratio = width_presets[1]
    for i, p in ipairs(width_presets) do
        if math.abs(col.width - p) < 0.05 then
            next_ratio = width_presets[(i % #width_presets) + 1]
            break
        end
    end
    col.width = next_ratio
    Quire.retile()
end

function Quire.focus_direction(dir)
    local col_idx, row_idx, ws, _ = Quire.find_window_pos(Quire.focused_window)
    if not col_idx then return end

    if dir == "left" and col_idx > 1 then
        local target = ws.columns[col_idx - 1].windows[math.min(row_idx, #ws.columns[col_idx - 1].windows)]
        wm.focus_window(target)
    elseif dir == "right" and col_idx < #ws.columns then
        local target = ws.columns[col_idx + 1].windows[math.min(row_idx, #ws.columns[col_idx + 1].windows)]
        wm.focus_window(target)
    elseif dir == "up" and row_idx > 1 then
        wm.focus_window(ws.columns[col_idx].windows[row_idx - 1])
    elseif dir == "down" and row_idx < #ws.columns[col_idx].windows then
        wm.focus_window(ws.columns[col_idx].windows[row_idx + 1])
    end
end

function Quire.move_column(dir)
    local col_idx, _, ws, _ = Quire.find_window_pos(Quire.focused_window)
    if not col_idx then return end

    if dir == "left" and col_idx > 1 then
        ws.columns[col_idx], ws.columns[col_idx - 1] = ws.columns[col_idx - 1], ws.columns[col_idx]
        Quire.retile()
    elseif dir == "right" and col_idx < #ws.columns then
        ws.columns[col_idx], ws.columns[col_idx + 1] = ws.columns[col_idx + 1], ws.columns[col_idx]
        Quire.retile()
    end
end

function Quire.consume_into_column(dir)
    local focused = Quire.focused_window
    if not focused or Quire.floating_windows[focused] then return end

    local col_idx, row_idx, ws, _ = Quire.find_window_pos(focused)
    if not col_idx then return end

    local target_col_idx = (dir == "left") and (col_idx - 1) or (col_idx + 1)
    if target_col_idx < 1 or target_col_idx > #ws.columns then return end

    table.remove(ws.columns[col_idx].windows, row_idx)
    if #ws.columns[col_idx].windows == 0 then
        table.remove(ws.columns, col_idx)
        if target_col_idx > col_idx then target_col_idx = target_col_idx - 1 end
    end

    table.insert(ws.columns[target_col_idx].windows, focused)
    Quire.retile()
end

function Quire.eject_from_column()
    local focused = Quire.focused_window
    if not focused or Quire.floating_windows[focused] then return end

    local col_idx, row_idx, ws, _ = Quire.find_window_pos(focused)
    if not col_idx or #ws.columns[col_idx].windows <= 1 then return end

    table.remove(ws.columns[col_idx].windows, row_idx)
    table.insert(ws.columns, col_idx + 1, { width = Quire.config.default_column_width, windows = { focused } })
    Quire.retile()
end

function Quire.move_window_stack(dir)
    local focused = Quire.focused_window
    if not focused then return end

    local col_idx, row_idx, ws, _ = Quire.find_window_pos(focused)
    if not col_idx then return end

    local wins = ws.columns[col_idx].windows
    if dir == "up" and row_idx > 1 then
        wins[row_idx], wins[row_idx - 1] = wins[row_idx - 1], wins[row_idx]
        Quire.retile()
    elseif dir == "down" and row_idx < #wins then
        wins[row_idx], wins[row_idx + 1] = wins[row_idx + 1], wins[row_idx]
        Quire.retile()
    end
end

function Quire.toggle_floating()
    local focused = Quire.focused_window
    if not focused then return end

    local sw, sh = wm.get_screen_size()

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

        local fw = math.floor(sw * 0.60)
        local fh = math.floor(sh * 0.70)
        local fx = math.floor((sw - fw) / 2)
        local fy = math.floor((sh - fh) / 2)

        Quire.floating_rects[focused] = { fx, fy, fw, fh }
        wm.move_window(focused, fx, fy, fw, fh)
        Quire.retile()
    end
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

Quire.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then return end

    if event_type == 0x0003 then
        local col_idx, _, _, existing_ws = Quire.find_window_pos(hwnd)
        if existing_ws and existing_ws ~= Quire.current_workspace then
            if os.clock() < (Quire.suppress_switch_until or 0) then
                return
            end
            Quire.switch_workspace(existing_ws)
            return
        end

        Quire.focused_window = hwnd
        if not col_idx and not Quire.floating_windows[hwnd] and wm.is_toplevel(hwnd) then
            add_window(hwnd, title, class)
        else
            Quire.retile()
        end
        return
    end

    if event_type == 0x8002 or event_type == 0x0017 then
        if not Quire.floating_windows[hwnd] and wm.is_toplevel(hwnd) then
            add_window(hwnd, title, class)
        end
        return
    end

    if event_type == 0x8001 then
        remove_window(hwnd, true)
        return
    end

    if event_type == 0x0016 then
        remove_window(hwnd, false)
        return
    end
end

local last_time = os.clock()

Quire.on_render_overlay = function()
    local now = os.clock()
    local dt = math.max(0.001, math.min(now - last_time, 0.033))
    last_time = now

    local cfg = Quire.config
    local sp = cfg.spring
    local sw, sh = wm.get_screen_size()

    camera_x, camera_vx = solve_spring(camera_x, camera_vx, camera_target_x, sp.stiffness, sp.damping, sp.mass, dt)
    camera_y, camera_vy = solve_spring(camera_y, camera_vy, 0.0, sp.stiffness, sp.damping, sp.mass, dt)

    if math.abs(camera_y) < 1.0 and math.abs(camera_vy) < 1.0 then
        if Quire.animating_ws then
            local old_ws = get_ws(Quire.animating_ws)
            for _, col in ipairs(old_ws.columns) do
                for _, hwnd in ipairs(col.windows) do
                    local target = Quire.window_targets[hwnd]
                    local tw = target and target.w or 800
                    local th = target and target.h or 600
                    wm.move_window(hwnd, -20000, 0, tw, th)
                end
            end
            Quire.animating_ws = nil
            if Quire.focused_window and wm.is_window_visible(Quire.focused_window) then
                wm.focus_window(Quire.focused_window)
            end
        end
    end

    if Quire.animating_ws then
        local old_ws = get_ws(Quire.animating_ws)
        local old_offset_y = math.floor(camera_y) - (Quire.anim_direction * sh)
        for _, col in ipairs(old_ws.columns) do
            for _, hwnd in ipairs(col.windows) do
                local target = Quire.window_targets[hwnd]
                if target then
                    wm.move_window(hwnd, target.world_x - math.floor(camera_x), target.y + old_offset_y, target.w, target.h)
                end
            end
        end
    end

    local ws = get_ws(Quire.current_workspace)
    for _, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col.windows) do
            local target = Quire.window_targets[hwnd]
            if target then
                local screen_target_x = target.world_x - math.floor(camera_x)
                local screen_target_y = target.y + math.floor(camera_y)
                local curr = Quire.window_currents[hwnd]

                if not curr then
                    curr = { x = screen_target_x, y = screen_target_y, w = target.w, h = target.h, vx = 0, vy = 0, vw = 0, vh = 0 }
                    Quire.window_currents[hwnd] = curr
                    wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                else
                    curr.x, curr.vx = solve_spring(curr.x, curr.vx, screen_target_x, sp.stiffness, sp.damping, sp.mass, dt)
                    curr.y, curr.vy = solve_spring(curr.y, curr.vy, screen_target_y, sp.stiffness, sp.damping, sp.mass, dt)
                    curr.w, curr.vw = solve_spring(curr.w, curr.vw, target.w, sp.stiffness, sp.damping, sp.mass, dt)
                    curr.h, curr.vh = solve_spring(curr.h, curr.vh, target.h, sp.stiffness, sp.damping, sp.mass, dt)

                    if curr.x > -curr.w - 100 and curr.x < sw + 100 then
                        wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                    end
                end
            end
        end
    end

    for _, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col.windows) do
            local curr = Quire.window_currents[hwnd]
            if curr and curr.x > -curr.w and curr.x < sw then
                local is_active = (hwnd == Quire.focused_window)
                local col_color = is_active and cfg.border_active or cfg.border_inactive
                ui.draw_rounded_rect(curr.x, curr.y, curr.w, curr.h, cfg.rounding, col_color[1], col_color[2], col_color[3], col_color[4], cfg.border_size)
            end
        end
    end

    alttab.draw()
    launcher.draw(1.0)
end

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
    elseif cmd == "preset" then
        Quire.cycle_column_preset()
        return "OK"
    elseif cmd == "close" then
        if Quire.focused_window then wm.close_window(Quire.focused_window) end
        return "OK"
    elseif cmd == "clients" then
        local out = {}
        for ws_id, ws in pairs(Quire.workspaces) do
            for c_i, col in ipairs(ws.columns) do
                for r_i, hwnd in ipairs(col.windows) do
                    table.insert(out, string.format("WS:%d Col:%d Row:%d [0x%X] %s", ws_id, c_i, r_i, hwnd, wm.get_window_title(hwnd)))
                end
            end
        end
        return #out > 0 and table.concat(out, "\n") or "No tiled clients"
    end
    return "ERROR: Unknown command " .. cmd
end

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
            ["TAB"] = 0x09, ["ESCAPE"] = 0x1B, ["MINUS"] = 0xBD, ["EQUAL"] = 0xBB,
            ["BRACKETLEFT"] = 0xDB, ["["] = 0xDB,
            ["BRACKETRIGHT"] = 0xDD, ["]"] = 0xDD,
            ["COMMA"] = 0xBC, ["PERIOD"] = 0xBE, ["SLASH"] = 0xBF, ["SEMICOLON"] = 0xBA
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

local existing = wm.enumerate_windows()
local ws1 = get_ws(1)
for _, hwnd in ipairs(existing) do
    local title = wm.get_window_title(hwnd)
    local class = wm.get_class_name(hwnd)
    if not should_ignore(hwnd, title, class) then
        if not apply_rules(hwnd, title, class) then
            table.insert(ws1.columns, {
                width = Quire.config.default_column_width,
                windows = { hwnd }
            })
            Quire.window_ws[hwnd] = 1
        end
    end
end
if #ws1.columns > 0 and #ws1.columns[1].windows > 0 then
    Quire.focused_window = ws1.columns[1].windows[1]
end

local config_path = wm.get_config_path()
if not pcall(dofile, config_path) then
    log("Config not found/error. Registering default Quire binds...")

    Quire.bind("Alt+H", function() Quire.focus_direction("left") end)
    Quire.bind("Alt+L", function() Quire.focus_direction("right") end)
    Quire.bind("Alt+K", function() Quire.focus_direction("up") end)
    Quire.bind("Alt+J", function() Quire.focus_direction("down") end)

    Quire.bind("Alt+Shift+H", function() Quire.move_column("left") end)
    Quire.bind("Alt+Shift+L", function() Quire.move_column("right") end)
    Quire.bind("Alt+Shift+Left", function() Quire.move_column("left") end)
    Quire.bind("Alt+Shift+Right", function() Quire.move_column("right") end)

    Quire.bind("Alt+Shift+BracketLeft", function() Quire.consume_into_column("left") end)
    Quire.bind("Alt+Shift+BracketRight", function() Quire.consume_into_column("right") end)
    Quire.bind("Alt+Shift+U", function() Quire.consume_into_column("left") end)
    Quire.bind("Alt+Shift+I", function() Quire.consume_into_column("right") end)
    Quire.bind("Alt+Shift+O", Quire.eject_from_column)

    Quire.bind("Alt+Shift+K", function() Quire.move_window_stack("up") end)
    Quire.bind("Alt+Shift+J", function() Quire.move_window_stack("down") end)
    Quire.bind("Alt+Shift+Up", function() Quire.move_window_stack("up") end)
    Quire.bind("Alt+Shift+Down", function() Quire.move_window_stack("down") end)

    Quire.bind("Alt+Q", function() if Quire.focused_window then wm.close_window(Quire.focused_window) end end)
    Quire.bind("Alt+F", Quire.toggle_fullscreen)
    Quire.bind("Alt+V", Quire.toggle_floating)

    Quire.bind("Alt+D", Quire.cycle_column_preset)
    Quire.bind("Alt+Minus", function() Quire.adjust_column_width(-0.05) end)
    Quire.bind("Alt+Equal", function() Quire.adjust_column_width(0.05) end)

    Quire.bind("Alt+Space", launcher.toggle)
    Quire.bind("Alt+Return", launcher.commit)

    for i = 1, 9 do
        Quire.bind("Alt+" .. i, function() Quire.switch_workspace(i) end)
        Quire.bind("Alt+Shift+" .. i, function() Quire.move_to_workspace(i) end)
    end
end

Quire.retile()