Quire = {}
Quire.hooks = {}
HyprWin = Quire

math.pow = math.pow or function(x, y)
    return x ^ y
end
package.path = package.path .. ";./scripts/?.lua;./scripts/ui/?.lua;./scripts/tiling/?.lua"
local anims = require("animsdef")
alttab = require("alttab")
launcher = require("launcher")
local minimap = require("minimap")
local ribbon_layout = require("ribbon")
local isle = require("isle")
Quire.minimap = minimap
Quire.isle = isle
Quire.launcher = launcher
Quire.alttab = alttab

Quire.layouts = {
    ribbon = ribbon_layout
}

local function get_layout(ws)
    local mode = (ws and ws.mode) or Quire.config.tiling_mode or "ribbon"
    return Quire.layouts[mode] or Quire.layouts.ribbon
end

Quire.theme = {
    rounding = 10,
    border_size = 2,
    font_family = "Segoe UI Variable",
    bg_color = {0.05, 0.05, 0.08, 0.92},
    border_color = {0.19, 0.20, 0.27, 0.60},
    active_border_color = {0.54, 0.71, 0.98, 1.00},
    accent_color = {0.54, 0.71, 0.98, 1.00},
    text_color = {0.90, 0.90, 0.95, 1.00},
    text_dim = {0.55, 0.55, 0.65, 0.80}
}

Quire.config = {
    fps_cap = 0,
    gaps_in = 8,
    gaps_out = 14,
    default_column_width = 1.0,
    rounding = Quire.theme.rounding,
    border_size = Quire.theme.border_size,
    border_active = Quire.theme.active_border_color,
    border_inactive = Quire.theme.border_color,
    idle_mode = "pulse",
    close_anim = "scale",
    move_easing = "spring",
    focus_follows_mouse = false,
    scratchpad_cmd = "alacritty.exe",
    enable_isle = true,
    spring = {
        stiffness = 170,
        damping = 24,
        mass = 1.0
    },
    enable_minimap = true,
    smart_gaps = true,
    smart_borders = false
}

Quire.current_workspace = 1
Quire.animating_ws = nil
Quire.anim_direction = 1
Quire.workspaces = {}
Quire.window_ws = {}
Quire.focused_window = nil
Quire.suppress_switch_until = 0.0

Quire.closing_windows = {}
Quire.transferring_windows = {}
Quire.alt_tab_zoom = 1.0

Quire.floating_windows = {}
Quire.floating_rects = {}
Quire.fullscreen_windows = {}

Quire.window_targets = {}
Quire.window_currents = {}
Quire.window_rules = {
    float = {}
}

Quire.overview_active = false
Quire.overview_zoom = 1.0

Quire.scratchpad_hwnd = nil
Quire.scratchpad_visible = false
Quire.scratchpad_y = -2000.0
Quire.scratchpad_vy = 0.0
Quire.expecting_scratchpad = false
Quire.scratchpad_prev_focus = nil

local function get_wall_time()
    return wm.get_time and wm.get_time() or os.clock()
end

local camera_x = 0.0
local camera_y = 0.0
local camera_target_x = 0.0
local camera_vx = 0.0
local camera_vy = 0.0

local hud_alpha = 0.0
local hud_timer = 0.0

local function trigger_hud()
    if Quire.minimap then
        Quire.minimap.trigger(1.4)
    end
end

function Quire.is_floating(hwnd)
    return Quire.floating_windows[hwnd] == true
end

function Quire.is_tiled(hwnd)
    local col_idx = Quire.find_window_pos(hwnd)
    return (col_idx ~= nil) and not Quire.floating_windows[hwnd]
end

local function get_ws(ws_id)
    ws_id = ws_id or Quire.current_workspace
    if not Quire.workspaces[ws_id] then
        Quire.workspaces[ws_id] = {
            columns = {}
        }
    end
    return Quire.workspaces[ws_id]
end

local function solve_spring(curr, vel, target, stiffness, damping, mass, dt)
    if dt <= 0.0 then
        return curr, vel
    end

    local diff = curr - target
    if math.abs(diff) < 0.15 and math.abs(vel) < 0.15 then
        return target, 0.0
    end

    dt = math.min(dt, 0.033)
    mass = math.max(0.05, mass or 1.0)
    damping = math.max(0.1, damping or 24.0)
    stiffness = math.max(1.0, stiffness or 170.0)

    local omega0 = math.sqrt(stiffness / mass)
    local zeta = damping / (2.0 * math.sqrt(stiffness * mass))

    if zeta < 0.999 then
        local omega_d = omega0 * math.sqrt(1.0 - zeta * zeta)
        local decay = math.exp(-zeta * omega0 * dt)
        local cos_val = math.cos(omega_d * dt)
        local sin_val = math.sin(omega_d * dt)

        local c1 = diff
        local c2 = (vel + zeta * omega0 * diff) / omega_d

        local next_pos = target + decay * (c1 * cos_val + c2 * sin_val)
        local next_vel = decay * ((vel * cos_val) - (c1 * omega_d + zeta * omega0 * c2) * sin_val)
        return next_pos, next_vel
    else
        local decay = math.exp(-omega0 * dt)
        local c1 = diff
        local c2 = vel + omega0 * diff
        local next_pos = target + decay * (c1 + c2 * dt)
        local next_vel = decay * (vel - (c1 + c2 * dt) * omega0 + c2)
        return next_pos, next_vel
    end
end

local ignored_classes = {"WorkerW", "Progman", "Shell_TrayWnd", "QuireOverlay", "Chrome_ChildWin_Templ", "GhostWindow",
                         "DesktopWindowXamlSource", "MSCTFIME UI", "IME", "CicMarshalWnd"}

function Quire.is_managed(hwnd)
    if Quire.floating_windows[hwnd] or Quire.scratchpad_hwnd == hwnd then
        return true
    end
    local col = Quire.find_window_pos(hwnd)
    return col ~= nil
end

local function should_ignore(hwnd, title, class)
    if not title or title:match("^%s*$") then
        return true
    end
    for _, ic in ipairs(ignored_classes) do
        if class == ic then
            return true
        end
    end
    local low_title = title:lower()
    if low_title == "picture in picture" or low_title:find("picture%-in%-picture") then
        return true
    end
    return false
end

function Quire.find_window_pos(hwnd)
    for ws_id, ws in pairs(Quire.workspaces) do
        if ws.columns then
            for col_idx, col in ipairs(ws.columns) do
                for row_idx, w in ipairs(col.windows) do
                    if w == hwnd then
                        return col_idx, row_idx, ws, ws_id
                    end
                end
            end
        end
    end
    return nil, nil, nil, nil
end

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

            Quire.floating_rects[hwnd] = {fx, fy, fw, fh}
            wm.move_window(hwnd, fx, fy, fw, fh)
            return true
        end
    end
    return false
end

local function layout_columns(ws_id, wx, wy, ww, wh, cfg)
    local ws = get_ws(ws_id)
    local cols = ws.columns
    if #cols == 0 then
        return 0
    end

    local is_smart = cfg.smart_gaps and (#cols == 1 and #cols[1].windows == 1) and not Quire.overview_active
    local gaps_in = is_smart and 0 or cfg.gaps_in
    local gaps_out = is_smart and 0 or cfg.gaps_out

    local avail_w = ww - (gaps_out * 2)
    local avail_h = wh - (gaps_out * 2)
    local cur_x = wx + gaps_out

    for c_idx, col in ipairs(cols) do
        local col_w = is_smart and avail_w or math.floor(avail_w * (col.width or cfg.default_column_width))
        local num_wins = #col.windows
        local total_gap_h = (num_wins - 1) * gaps_in
        local win_h = math.floor((avail_h - total_gap_h) / math.max(1, num_wins))

        local cur_y = wy + gaps_out
        for r_idx, hwnd in ipairs(col.windows) do
            local h = win_h
            if r_idx == num_wins then
                h = (wy + gaps_out + avail_h) - cur_y
            end

            Quire.window_targets[hwnd] = {
                world_x = cur_x,
                y = cur_y,
                w = col_w,
                h = h
            }
            cur_y = cur_y + h + gaps_in
        end
        cur_x = cur_x + col_w + gaps_in
    end
    return cur_x - gaps_in + gaps_out
end

function Quire.retile()
    local wx, wy, ww, wh = wm.get_work_area()
    local cfg = Quire.config
    local ws = get_ws(Quire.current_workspace)
    local layout = get_layout(ws)

    local fs_win = nil
    for hwnd, _ in pairs(Quire.fullscreen_windows) do
        local _, _, win_ws, _ = Quire.find_window_pos(hwnd)
        if win_ws == ws and wm.is_window_visible(hwnd) then
            fs_win = hwnd
            break
        end
    end

    if fs_win then
        Quire.window_targets[fs_win] = {
            world_x = wx,
            y = wy,
            w = ww,
            h = wh
        }
        camera_target_x = 0
        return
    end

    layout.clean_columns(ws, function(hwnd)
        return wm.is_window(hwnd) and not Quire.floating_windows[hwnd]
    end)

    if Quire.animating_ws then
        local anim_ws = get_ws(Quire.animating_ws)
        local anim_layout = get_layout(anim_ws)
        local anim_targets = anim_layout.arrange(anim_ws, wx, wy, ww, wh, cfg, nil, false)
        for h, t in pairs(anim_targets) do
            Quire.window_targets[h] = t
        end
    end

    local is_scrolling = get_wall_time() < (Quire.scroll_active_until or 0.0)
    local check_focus = (not is_scrolling and not Quire.floating_windows[Quire.focused_window]) and Quire.focused_window or nil

    local targets, target_cam_x, max_cam_x, total_w = layout.arrange(
        ws, wx, wy, ww, wh, cfg, check_focus, Quire.overview_active
    )

    for h, t in pairs(targets) do
        Quire.window_targets[h] = t
    end

    if target_cam_x and not is_scrolling then
        camera_target_x = target_cam_x
    end

    camera_target_x = math.max(0, math.min(max_cam_x, camera_target_x))

    for _, c in pairs(Quire.window_currents) do
        c.needs_sync = true
    end
end

function Quire.toggle_overview()
    Quire.overview_active = not Quire.overview_active
    if not Quire.overview_active and Quire.focused_window then
        wm.focus_window(Quire.focused_window)
    end
    Quire.retile()
    trigger_hud()
end

function Quire.toggle_scratchpad()
    local fg = wm.get_foreground_window()
    local current = (fg and fg ~= 0) and fg or Quire.focused_window

    if not Quire.scratchpad_hwnd or not wm.is_window(Quire.scratchpad_hwnd) then
        if current and current ~= Quire.scratchpad_hwnd then
            Quire.scratchpad_prev_focus = current
        end
        Quire.expecting_scratchpad = true
        wm.spawn(Quire.config.scratchpad_cmd or "alacritty.exe")
        return
    end

    Quire.scratchpad_visible = not Quire.scratchpad_visible
    if Quire.scratchpad_visible then
        if current and current ~= Quire.scratchpad_hwnd then
            Quire.scratchpad_prev_focus = current
        end
        wm.cloak_window(Quire.scratchpad_hwnd, false)
        if wm.set_topmost then
            wm.set_topmost(Quire.scratchpad_hwnd, true)
        end
        wm.focus_window(Quire.scratchpad_hwnd)
        Quire.focused_window = Quire.scratchpad_hwnd
    else
        local target = Quire.scratchpad_prev_focus
        if target and wm.is_window(target) and not Quire.closing_windows[target] then
            Quire.focused_window = target
            wm.focus_window(target)
        else
            local ws = get_ws(Quire.current_workspace)
            local fallback = nil
            for _, col in ipairs(ws.columns) do
                for _, w in ipairs(col.windows) do
                    if wm.is_window(w) then
                        fallback = w
                        break
                    end
                end
                if fallback then
                    break
                end
            end
            Quire.focused_window = fallback
            if fallback then
                wm.focus_window(fallback)
            end
        end
    end
    trigger_hud()
end

function Quire.mark_scratchpad()
    local fg = wm.get_foreground_window()
    local focused = (fg and fg ~= 0 and
                        (fg == Quire.scratchpad_hwnd or Quire.find_window_pos(fg) or Quire.floating_windows[fg])) and fg or
                        Quire.focused_window
    if not focused then
        return
    end

    if Quire.scratchpad_hwnd == focused then
        Quire.scratchpad_hwnd = nil
        Quire.scratchpad_visible = false
        Quire.floating_windows[focused] = nil
        Quire.floating_rects[focused] = nil
        if wm.set_topmost then
            wm.set_topmost(focused, false)
        end
        wm.cloak_window(focused, false)

        local rx, ry, rw, rh = wm.get_window_rect(focused)
        Quire.window_currents[focused] = {
            world_x = rx + camera_x,
            world_y = ry - camera_y,
            x = rx,
            y = ry,
            w = rw,
            h = rh,
            vx = 0,
            vy = 0,
            vw = 0,
            vh = 0,
            needs_sync = true
        }

        local ws = get_ws(Quire.current_workspace)
        table.insert(ws.columns, {
            width = Quire.config.default_column_width,
            windows = {focused}
        })
        Quire.window_ws[focused] = Quire.current_workspace
        Quire.focused_window = focused
        Quire.retile()
        trigger_hud()
        return
    end

    local col_idx, row_idx, ws = Quire.find_window_pos(focused)
    if col_idx then
        table.remove(ws.columns[col_idx].windows, row_idx)
        if #ws.columns[col_idx].windows == 0 then
            table.remove(ws.columns, col_idx)
        end
    end

    Quire.floating_windows[focused] = true
    Quire.scratchpad_hwnd = focused
    Quire.scratchpad_visible = true
    Quire.window_currents[focused] = nil
    Quire.window_targets[focused] = nil
    if wm.set_topmost then
        wm.set_topmost(focused, true)
    end
    Quire.retile()
    trigger_hud()
end

Quire.on_mouse_down = function(mx, my)
    if Quire.config.enable_minimap ~= false and Quire.minimap and Quire.minimap.on_mouse_down then
        if Quire.minimap.on_mouse_down(mx, my) then
            return true
        end
    end

    if Quire.config.enable_isle ~= false and Quire.isle and Quire.isle.on_mouse_down then
        return Quire.isle.on_mouse_down(mx, my)
    end
    return false
end

local original_on_keyboard_input = Quire.on_keyboard_input
Quire.on_keyboard_input = function(vk, char, ctrl, shift)
    if Quire.isle and Quire.isle.on_keyboard_input then
        if Quire.isle.on_keyboard_input(vk, char, ctrl, shift) then
            return true
        end
    end

    if Quire.launcher_active and launcher.on_key then
        return launcher.on_key(vk, char)
    end
    return false
end

Quire.on_mouse_move = function(mx, my)
    if Quire.config.enable_isle ~= false and Quire.isle and Quire.isle.update_mouse then
        Quire.isle.update_mouse(mx, my)
    end

    if not Quire.config.focus_follows_mouse or Quire.overview_active then
        return
    end

    if Quire.focused_window then
        if Quire.floating_windows[Quire.focused_window] or Quire.focused_window == Quire.scratchpad_hwnd then
            return
        end
    end

    if math.abs(camera_x - camera_target_x) > 1.0 then
        return
    end
    if get_wall_time() < (Quire.scroll_active_until or 0.0) then
        return
    end

    if Quire.scratchpad_hwnd and Quire.scratchpad_visible and wm.is_window(Quire.scratchpad_hwnd) then
        local rx, ry, rw, rh = wm.get_window_rect(Quire.scratchpad_hwnd)
        if mx >= rx and mx <= (rx + rw) and my >= ry and my <= (ry + rh) then
            if Quire.scratchpad_hwnd ~= Quire.focused_window then
                Quire.focused_window = Quire.scratchpad_hwnd
                wm.focus_window(Quire.scratchpad_hwnd)
            end
            return
        end
    end

    for hwnd, _ in pairs(Quire.floating_windows) do
        if wm.is_window(hwnd) then
            local rx, ry, rw, rh = wm.get_window_rect(hwnd)
            if mx >= rx and mx <= (rx + rw) and my >= ry and my <= (ry + rh) then
                if hwnd ~= Quire.focused_window then
                    Quire.focused_window = hwnd
                    wm.focus_window(hwnd)
                end
                return
            end
        end
    end

    local ws = get_ws(Quire.current_workspace)
    for _, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col.windows) do
            local curr = Quire.window_currents[hwnd]
            if curr and mx >= curr.x and mx <= (curr.x + curr.w) and my >= curr.y and my <= (curr.y + curr.h) then
                if hwnd ~= Quire.focused_window then
                    Quire.focused_window = hwnd
                    wm.focus_window(hwnd)
                end
                return
            end
        end
    end
end

Quire.pending_session = {}

local function serialize_table(val, indent)
    indent = indent or ""
    local t = type(val)
    if t == "number" or t == "boolean" then
        return tostring(val)
    elseif t == "string" then
        return string.format("%q", val)
    elseif t == "table" then
        local parts = {}
        for k, v in pairs(val) do
            local key_str = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or
                                ("[" .. serialize_table(k) .. "]")
            table.insert(parts, indent .. "  " .. key_str .. " = " .. serialize_table(v, indent .. "  "))
        end
        return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
    end
    return "nil"
end

function Quire.save_session()
    local session = {
        current_ws = Quire.current_workspace,
        workspaces = {}
    }

    for ws_id, ws in pairs(Quire.workspaces) do
        if ws.columns and #ws.columns > 0 then
            local cols_data = {}
            for _, col in ipairs(ws.columns) do
                local win_data = {}
                for _, hwnd in ipairs(col.windows) do
                    if wm.is_window(hwnd) then
                        local proc = wm.get_process_name and wm.get_process_name(hwnd) or ""
                        local class = wm.get_class_name(hwnd)
                        local title = wm.get_window_title(hwnd)
                        table.insert(win_data, {
                            proc = proc,
                            class = class,
                            title = title
                        })
                    end
                end
                if #win_data > 0 then
                    table.insert(cols_data, {
                        width = col.width or Quire.config.default_column_width,
                        windows = win_data
                    })
                end
            end
            if #cols_data > 0 then
                session.workspaces[ws_id] = cols_data
            end
        end
    end

    local session_path = wm.get_config_path():gsub("config%.lua$", "session.lua")
    local f = io.open(session_path, "w")
    if f then
        f:write("return " .. serialize_table(session))
        f:close()
        log("Session saved successfully!")
        trigger_hud()
    end
end

function Quire.restore_session()
    local session_path = wm.get_config_path():gsub("config%.lua$", "session.lua")
    local fn = loadfile(session_path)
    if not fn then
        log("No saved session found at " .. session_path)
        return
    end

    local ok, session = pcall(fn)
    if not ok or not session or not session.workspaces then
        log("Failed to parse saved session")
        return
    end

    local all_hwnds = wm.enumerate_windows and wm.enumerate_windows() or {}
    local available_windows = {}

    for _, hwnd in ipairs(all_hwnds) do
        if not should_ignore(hwnd, wm.get_window_title(hwnd), wm.get_class_name(hwnd)) then
            local proc = (wm.get_process_name and wm.get_process_name(hwnd) or ""):lower()
            local class = wm.get_class_name(hwnd):lower()
            table.insert(available_windows, {
                hwnd = hwnd,
                proc = proc,
                class = class,
                used = false
            })
        end
    end

    Quire.workspaces = {}
    Quire.window_ws = {}
    Quire.pending_session = {}

    for ws_id, cols_data in pairs(session.workspaces) do
        local ws = get_ws(ws_id)
        ws.columns = {}

        for c_idx, col_info in ipairs(cols_data) do
            local col = {
                width = col_info.width or Quire.config.default_column_width,
                windows = {}
            }

            for _, saved_win in ipairs(col_info.windows) do
                local target_proc = saved_win.proc:lower()
                local target_class = saved_win.class:lower()
                local matched_hwnd = nil

                for _, candidate in ipairs(available_windows) do
                    if not candidate.used and candidate.proc == target_proc then
                        matched_hwnd = candidate.hwnd
                        candidate.used = true
                        break
                    end
                end

                if matched_hwnd then
                    table.insert(col.windows, matched_hwnd)
                    Quire.window_ws[matched_hwnd] = ws_id
                    if wm.track_window then
                        wm.track_window(matched_hwnd)
                    end
                    if ws_id ~= Quire.current_workspace then
                        wm.cloak_window(matched_hwnd, true)
                    else
                        wm.cloak_window(matched_hwnd, false)
                    end
                else
                    if saved_win.proc ~= "" then
                        wm.spawn(saved_win.proc)
                        table.insert(Quire.pending_session, {
                            proc = target_proc,
                            ws_id = ws_id,
                            c_idx = c_idx
                        })
                    end
                end
            end

            if #col.windows > 0 then
                table.insert(ws.columns, col)
            end
        end
    end

    if session.current_ws then
        Quire.current_workspace = session.current_ws
    end

    local cur_ws = get_ws(Quire.current_workspace)
    if #cur_ws.columns > 0 and #cur_ws.columns[1].windows > 0 then
        Quire.focused_window = cur_ws.columns[1].windows[1]
        wm.focus_window(Quire.focused_window)
    end

    log("Session restored!")
    trigger_hud()
    Quire.retile()
end

local function add_window(hwnd, title, class)
    if Quire.expecting_scratchpad then
        Quire.expecting_scratchpad = false
        Quire.floating_windows[hwnd] = true
        Quire.scratchpad_hwnd = hwnd
        Quire.scratchpad_visible = true
        if wm.track_window then wm.track_window(hwnd) end
        trigger_hud()
        return
    end

    local proc_name = (wm.get_process_name and wm.get_process_name(hwnd) or ""):lower()
    for i, pending in ipairs(Quire.pending_session) do
        if pending.proc == proc_name then
            table.remove(Quire.pending_session, i)
            local ws = get_ws(pending.ws_id)
            if not ws.columns[pending.c_idx] then
                ws.columns[pending.c_idx] = {
                    width = Quire.config.default_column_width,
                    windows = {}
                }
            end
            table.insert(ws.columns[pending.c_idx].windows, hwnd)
            Quire.window_ws[hwnd] = pending.ws_id
            if wm.track_window then wm.track_window(hwnd) end
            if pending.ws_id ~= Quire.current_workspace then
                wm.cloak_window(hwnd, true)
            else
                wm.cloak_window(hwnd, false)
                Quire.focused_window = hwnd
                wm.focus_window(hwnd)
            end
            Quire.retile()
            trigger_hud()
            return
        end
    end

    if Quire.floating_windows[hwnd] then
        return
    end
    if apply_rules(hwnd, title, class) then
        if wm.track_window then wm.track_window(hwnd) end
        return
    end

    local col_idx = Quire.find_window_pos(hwnd)
    if col_idx then
        return
    end

    local ws = get_ws(Quire.current_workspace)
    local layout = get_layout(ws)
    layout.add_window(ws, hwnd, Quire.focused_window, Quire.config.default_column_width)

    if wm.track_window then
        wm.track_window(hwnd)
    end

    Quire.window_ws[hwnd] = Quire.current_workspace
    Quire.focused_window = hwnd
    if Quire.hooks.on_window_open then
        pcall(Quire.hooks.on_window_open, hwnd, title, class)
    end
    trigger_hud()
    Quire.retile()
end

local function remove_window(hwnd, is_destroy)
    if wm.set_topmost then
        wm.set_topmost(hwnd, false)
    end
    if is_destroy and wm.untrack_window then
        wm.untrack_window(hwnd)
    end

    local was_scratchpad = (hwnd == Quire.scratchpad_hwnd)
    if was_scratchpad then
        Quire.scratchpad_hwnd = nil
        Quire.scratchpad_visible = false
    end

    if is_destroy then
        Quire.floating_windows[hwnd] = nil
        Quire.floating_rects[hwnd] = nil
    end

    Quire.fullscreen_windows[hwnd] = nil
    Quire.window_targets[hwnd] = nil
    Quire.window_currents[hwnd] = nil
    Quire.window_ws[hwnd] = nil
    Quire.closing_windows[hwnd] = nil
    Quire.transferring_windows[hwnd] = nil

    if was_scratchpad then
        local prev = Quire.scratchpad_prev_focus
        if prev and wm.is_window(prev) and not Quire.closing_windows[prev] then
            Quire.focused_window = prev
            wm.focus_window(prev)
        end
        trigger_hud()
        Quire.retile()
        return
    end

    local col_idx, row_idx, ws = Quire.find_window_pos(hwnd)
    if not col_idx then
        return
    end

    local layout = get_layout(ws)
    local next_focus = layout.remove_window(ws, hwnd)

    if Quire.focused_window == hwnd then
        Quire.focused_window = next_focus
        if next_focus then
            Quire.suppress_switch_until = get_wall_time() + 0.4
            wm.focus_window(next_focus)
        end
    end

    if Quire.hooks.on_window_close then
        pcall(Quire.hooks.on_window_close, hwnd)
    end
    trigger_hud()
    Quire.retile()
end

local function park_inactive_workspaces()
    for ws_id, ws in pairs(Quire.workspaces) do
        if ws_id ~= Quire.current_workspace and ws_id ~= Quire.animating_ws then
            for _, col in ipairs(ws.columns) do
                for _, hwnd in ipairs(col.windows) do
                    wm.cloak_window(hwnd, true)
                end
            end
        else
            for _, col in ipairs(ws.columns) do
                for _, hwnd in ipairs(col.windows) do
                    wm.cloak_window(hwnd, false)
                end
            end
        end
    end
end

function Quire.switch_workspace(target_ws)
    if target_ws == Quire.current_workspace then
        return
    end

    local old_ws = Quire.current_workspace
    local _, sh = wm.get_screen_size()
    local direction = (target_ws > old_ws) and 1 or -1

    Quire.animating_ws = old_ws
    Quire.anim_direction = direction
    Quire.current_workspace = target_ws
    Quire.suppress_switch_until = get_wall_time() + 1.2

    park_inactive_workspaces()

    camera_y = direction * sh
    camera_vy = 0.0
    Quire.cam_anim_y = nil

    camera_x = 0.0
    camera_target_x = 0.0
    camera_vx = 0.0
    Quire.cam_anim = nil

    local new_ws = get_ws(target_ws)
    for _, col in ipairs(new_ws.columns) do
        for _, hwnd in ipairs(col.windows) do
            local target = Quire.window_targets[hwnd]
            if target then
                local curr = Quire.window_currents[hwnd]
                if not curr then
                    curr = {
                        world_x = target.world_x,
                        world_y = target.y,
                        x = target.world_x,
                        y = target.y + (direction * sh),
                        w = target.w,
                        h = target.h,
                        vx = 0,
                        vy = 0,
                        vw = 0,
                        vh = 0,
                        needs_sync = true
                    }
                    Quire.window_currents[hwnd] = curr
                else
                    curr.world_x = target.world_x
                    curr.world_y = target.y
                    curr.vx = 0.0
                    curr.vy = 0.0
                    curr.w = target.w
                    curr.h = target.h
                    curr.vw = 0.0
                    curr.vh = 0.0
                    curr.x = target.world_x
                    curr.y = target.y + (direction * sh)
                    curr.needs_sync = true
                end
            end
        end
    end

    if #new_ws.columns > 0 and #new_ws.columns[1].windows > 0 then
        Quire.focused_window = new_ws.columns[1].windows[1]
        wm.focus_window(Quire.focused_window)
    else
        Quire.focused_window = nil
    end

    trigger_hud()
    if Quire.hooks.on_workspace_change then
        pcall(Quire.hooks.on_workspace_change, old_ws, target_ws)
    end
    Quire.retile()
end

function Quire.move_to_workspace(target_ws)
    local fg = wm.get_foreground_window()
    local focused = Quire.focused_window

    if fg and fg ~= 0 and Quire.find_window_pos(fg) then
        focused = fg
        Quire.focused_window = fg
    end

    if not focused or Quire.floating_windows[focused] then
        return
    end

    local col_idx, row_idx, src_ws = Quire.find_window_pos(focused)
    if not col_idx then
        return
    end

    local col = src_ws.columns[col_idx]
    table.remove(col.windows, row_idx)
    local col_w = col.width
    if #col.windows == 0 then
        table.remove(src_ws.columns, col_idx)
    end

    local dest_ws = get_ws(target_ws)
    table.insert(dest_ws.columns, {
        width = col_w,
        windows = {focused}
    })
    Quire.window_ws[focused] = target_ws

    local _, sh = wm.get_screen_size()
    local curr = Quire.window_currents[focused] or {
        x = 0,
        y = 0,
        w = 800,
        h = 600
    }

    Quire.transferring_windows[focused] = {
        start_x = curr.x,
        start_y = curr.y,
        target_y = curr.y + sh,
        w = curr.w,
        h = curr.h,
        start_time = get_wall_time(),
        duration = 0.35,
        target_ws = target_ws
    }

    Quire.window_targets[focused] = nil
    Quire.window_currents[focused] = nil

    local next_col = src_ws.columns[col_idx] or src_ws.columns[col_idx - 1]
    Quire.focused_window = (next_col and #next_col.windows > 0) and next_col.windows[1] or nil
    if Quire.focused_window then
        wm.focus_window(Quire.focused_window)
    end

    trigger_hud()
    Quire.retile()
end

function Quire.cycle_column_preset()
    local ws = get_ws(Quire.current_workspace)
    local layout = get_layout(ws)
    if layout.cycle_preset then
        layout.cycle_preset(ws, Quire.focused_window)
        trigger_hud()
        Quire.retile()
    end
end

function Quire.cycle_workspace(step)
    local cur = Quire.current_workspace
    local next_ws = cur + step
    if next_ws < 1 then
        next_ws = 9
    end
    if next_ws > 9 then
        next_ws = 1
    end
    Quire.switch_workspace(next_ws)
end

function Quire.move_window_to_monitor(dir)
    local focused = Quire.focused_window
    if not focused then
        return
    end

    local col_idx, row_idx, ws = Quire.find_window_pos(focused)
    if col_idx then
        table.remove(ws.columns[col_idx].windows, row_idx)
        if #ws.columns[col_idx].windows == 0 then
            table.remove(ws.columns, col_idx)
        end
        Quire.retile()
    end

    Quire.floating_windows[focused] = true
    Quire.window_targets[focused] = nil
    Quire.window_currents[focused] = nil

    local step = (dir == "left") and -1 or 1
    wm.move_to_monitor(focused, step)

    local rx, ry, rw, rh = wm.get_window_rect(focused)
    Quire.floating_rects[focused] = {rx, ry, rw, rh}
end

function Quire.focus_direction(dir)
    if Quire.launcher_active then
        if dir == "up" then
            launcher.navigate("up")
        elseif dir == "down" then
            launcher.navigate("down")
        end
        return
    end

    local ws = get_ws(Quire.current_workspace)
    local layout = get_layout(ws)
    local target = layout.focus_direction(ws, Quire.focused_window, dir)

    if not target then
        local fg = wm.get_foreground_window()
        if fg and fg ~= 0 then
            target = layout.focus_direction(ws, fg, dir)
        end
    end

    if target then
        Quire.focused_window = target
        wm.focus_window(target)
        Quire.retile()
    end
    trigger_hud()
end


function Quire.move_column(dir)
    local ws = get_ws(Quire.current_workspace)
    local layout = get_layout(ws)
    if layout.move_column and layout.move_column(ws, Quire.focused_window, dir) then
        Quire.retile()
        trigger_hud()
    end
end

function Quire.toggle_floating()
    local fg = wm.get_foreground_window()
    local focused = (fg and fg ~= 0 and
                        (fg == Quire.scratchpad_hwnd or Quire.find_window_pos(fg) or Quire.floating_windows[fg])) and fg or
                        Quire.focused_window
    if not focused then
        return
    end

    if Quire.scratchpad_hwnd == focused then
        Quire.mark_scratchpad()
        return
    end

    local wx, wy, ww, wh = wm.get_work_area()

    if Quire.floating_windows[focused] then
        Quire.floating_windows[focused] = nil
        Quire.floating_rects[focused] = nil
        if wm.set_topmost then
            wm.set_topmost(focused, false)
        end

        local rx, ry, rw, rh = wm.get_window_rect(focused)
        Quire.window_currents[focused] = {
            world_x = rx + camera_x,
            world_y = ry - camera_y,
            x = rx,
            y = ry,
            w = rw,
            h = rh,
            vx = 0,
            vy = 0,
            vw = 0,
            vh = 0,
            needs_sync = true
        }

        local ws = get_ws(Quire.current_workspace)
        table.insert(ws.columns, {
            width = Quire.config.default_column_width,
            windows = {focused}
        })
        Quire.window_ws[focused] = Quire.current_workspace
        Quire.focused_window = focused
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

        Quire.floating_rects[focused] = {fx, fy, fw, fh}
        wm.move_window(focused, fx, fy, fw, fh)
        if wm.set_topmost then
            wm.set_topmost(focused, true)
        end
        wm.focus_window(focused)
        Quire.focused_window = focused
        Quire.retile()
    end
    trigger_hud()
end

function Quire.toggle_fullscreen()
    local focused = Quire.focused_window
    if not focused then
        return
    end

    Quire.fullscreen_windows[focused] = not Quire.fullscreen_windows[focused] or nil
    trigger_hud()
    Quire.retile()
end

function Quire.safe_close_window(hwnd)
    if not hwnd or Quire.closing_windows[hwnd] then
        return
    end

    if wm.set_topmost then
        wm.set_topmost(hwnd, false)
    end

    local rx, ry, rw, rh = wm.get_window_rect(hwnd)
    Quire.closing_windows[hwnd] = {
        x = rx,
        y = ry,
        w = rw,
        h = rh,
        start_time = get_wall_time(),
        duration = 0.22,
        mode = Quire.config.close_anim
    }
end

Quire.dispatch_event = function(event_type, hwnd, title)
    local class = wm.get_class_name(hwnd)
    if should_ignore(hwnd, title, class) then
        return
    end

    if event_type == 0x000B then
        if get_wall_time() < (Quire.scroll_active_until or 0.0) then
            return
        end
        local col, _, _, ws_id = Quire.find_window_pos(hwnd)
        if col and not Quire.floating_windows[hwnd] and ws_id == Quire.current_workspace then
            local rx, ry = wm.get_window_rect(hwnd)
            if rx and rx > -1000 then
                local curr = Quire.window_currents[hwnd]
                if curr then
                    curr.x = rx
                    curr.y = ry
                    curr.needs_sync = true
                end
                Quire.retile()
            end
        end
        return
    end

    if event_type == 0x0003 then
        if alttab and alttab.record_focus then
            alttab.record_focus(hwnd)
        end
        local col_idx, _, _, existing_ws = Quire.find_window_pos(hwnd)

        if existing_ws and existing_ws ~= Quire.current_workspace then
            if Quire.focused_window and wm.is_window_visible(Quire.focused_window) then
                wm.focus_window(Quire.focused_window)
            end
            return
        end

        Quire.focused_window = hwnd
        if Quire.hooks.on_window_focus then
            pcall(Quire.hooks.on_window_focus, hwnd, title, class)
        end

        if not col_idx and not Quire.floating_windows[hwnd] and wm.is_toplevel(hwnd) then
            add_window(hwnd, title, class)
        else
            Quire.retile()
        end
        return
    end

    if event_type == 0x8000 or event_type == 0x8002 or event_type == 0x0017 or event_type == 0x800C then
        local col_idx = Quire.find_window_pos(hwnd)
        if not col_idx and not Quire.floating_windows[hwnd] and wm.is_toplevel(hwnd) then
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

local last_render_time = get_wall_time()

local function draw_hud(sw, sh, dt)
    if hud_timer > 0 then
        hud_timer = hud_timer - dt
        hud_alpha = math.min(1.0, hud_alpha + dt * 6.0)
    else
        hud_alpha = math.max(0.0, hud_alpha - dt * 3.0)
    end

    if hud_alpha < 0.01 then
        return
    end

    local wx, wy, ww, wh = wm.get_work_area()
    local ws = get_ws(Quire.current_workspace)
    local cur_col_idx = 1
    local cur_ratio = 1.0

    if Quire.focused_window then
        local c, _, win_ws = Quire.find_window_pos(Quire.focused_window)
        if c and win_ws == ws and ws.columns and ws.columns[c] then
            cur_col_idx = c
            cur_ratio = ws.columns[c].width or 1.0
        end
    end

    if not ws.columns or #ws.columns == 0 then
        cur_col_idx = 0
        cur_ratio = 1.0
    else
        cur_col_idx = math.max(1, math.min(#ws.columns, cur_col_idx))
        if ws.columns[cur_col_idx] and ws.columns[cur_col_idx].width then
            cur_ratio = ws.columns[cur_col_idx].width
        end
    end

    local dots = {}
    if ws.columns then
        for i = 1, #ws.columns do
            table.insert(dots, (i == cur_col_idx) and "[*]" or "[ ]")
        end
    end
    local ribbon_str = (#dots > 0) and table.concat(dots, " ") or "EMPTY"
    local pct_str = math.floor(cur_ratio * 100) .. "%"
    local hud_text = string.format("WS %d  |  %s  |  %s", Quire.current_workspace, ribbon_str, pct_str)

    local font = Quire.theme.font_family
    local tw = ui.measure_text(hud_text, 11, font)
    local pw = tw + 32
    local ph = 30
    local px = wx + math.floor((ww - pw) / 2)
    local py = wy + wh - ph - 16

    ui.fill_rounded_rect(px, py, pw, ph, 15, 0.04, 0.04, 0.06, 0.85 * hud_alpha)
    ui.draw_rounded_rect(px, py, pw, ph, 15, 0.54, 0.71, 0.98, 0.40 * hud_alpha, 1.0)
    ui.draw_text(hud_text, px + 16, py + 7, 11, 0.90, 0.92, 0.96, hud_alpha, font)
end

Quire.on_render_overlay = function()
    local now = get_wall_time()
    local dt = math.max(0.001, math.min(now - last_render_time, 0.05))
    last_render_time = now

    local sw, sh = wm.get_screen_size()
    local wx, wy, ww, wh = wm.get_work_area()
    local cfg = Quire.config
    local sp = cfg.spring

    for hwnd, tr in pairs(Quire.transferring_windows) do
        local progress = (now - tr.start_time) / tr.duration
        if progress >= 1.0 then
            wm.move_window(hwnd, -20000, -20000, 0, 0)
            wm.set_window_opacity(hwnd, 1.0)
            Quire.transferring_windows[hwnd] = nil
        else
            local ease_val = anims.easings.ease_in(progress)
            local cur_y = math.floor(tr.start_y + (tr.target_y - tr.start_y) * ease_val)
            wm.move_window(hwnd, tr.start_x, cur_y, tr.w, tr.h)
            wm.set_window_opacity(hwnd, 1.0 - ease_val)
        end
    end

    for hwnd, cl in pairs(Quire.closing_windows) do
        local progress = (now - cl.start_time) / cl.duration
        if progress >= 1.0 then
            wm.close_window(hwnd)
            Quire.closing_windows[hwnd] = nil
        else
            local ease_val = anims.easings.ease_out(progress)
            local gx, gy, gw, gh, alpha = anims.calc_close_geometry(cl.mode, ease_val, cl.x, cl.y, cl.w, cl.h, sh)
            wm.move_window(hwnd, gx, gy, gw, gh)
            wm.set_window_opacity(hwnd, alpha)
        end
    end

    local easing_name = cfg.move_easing or "spring"
    local ease_fn = anims.easings[easing_name]
    local anim_dur = math.max(0.01, cfg.move_duration or 0.28)
    local is_touch_scrolling = now < (Quire.scroll_active_until or 0.0)

    if is_touch_scrolling or not ease_fn or easing_name == "spring" then
        camera_x, camera_vx = solve_spring(camera_x, camera_vx, camera_target_x, sp.stiffness, sp.damping, sp.mass, dt)
        Quire.cam_anim = nil
    else
        if not Quire.cam_anim or Quire.cam_anim.target ~= camera_target_x then
            Quire.cam_anim = {
                start_x = camera_x,
                target = camera_target_x,
                start_time = now,
                duration = anim_dur
            }
        end
        local ct = math.min(1.0, (now - Quire.cam_anim.start_time) / Quire.cam_anim.duration)
        camera_x = Quire.cam_anim.start_x + (Quire.cam_anim.target - Quire.cam_anim.start_x) * ease_fn(ct)
        camera_vx = 0.0
    end

    if not ease_fn or easing_name == "spring" then
        camera_y, camera_vy = solve_spring(camera_y, camera_vy, 0.0, sp.stiffness, sp.damping, sp.mass, dt)
    else
        if Quire.animating_ws then
            if not Quire.cam_anim_y or Quire.cam_anim_y.ws ~= Quire.current_workspace then
                Quire.cam_anim_y = {
                    ws = Quire.current_workspace,
                    start_y = camera_y,
                    target = 0.0,
                    start_time = now,
                    duration = anim_dur
                }
            end
            local ct = math.min(1.0, (now - Quire.cam_anim_y.start_time) / Quire.cam_anim_y.duration)
            camera_y = Quire.cam_anim_y.start_y + (Quire.cam_anim_y.target - Quire.cam_anim_y.start_y) * ease_fn(ct)
            if ct >= 1.0 then
                camera_y = 0.0
                camera_vy = 0.0
                Quire.cam_anim_y = nil
            else
                camera_vy = 10.0
            end
        else
            camera_y, camera_vy = solve_spring(camera_y, camera_vy, 0.0, sp.stiffness, sp.damping, sp.mass, dt)
        end
    end

    if math.abs(camera_y) < 1.0 and math.abs(camera_vy) < 1.0 then
        if Quire.animating_ws then
            local old_ws = get_ws(Quire.animating_ws)
            for _, col in ipairs(old_ws.columns) do
                for _, hwnd in ipairs(col.windows) do
                    wm.cloak_window(hwnd, true)
                end
            end
            Quire.animating_ws = nil
            if Quire.focused_window and wm.is_window(Quire.focused_window) then
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
                    wm.move_window(hwnd, target.world_x - math.floor(camera_x), target.y + old_offset_y, target.w,
                        target.h)
                end
            end
        end
    end

    local ws = get_ws(Quire.current_workspace)
    local cam_floor_x = math.floor(camera_x)
    local cam_floor_y = math.floor(camera_y)

    local target_zoom = Quire.overview_active and 0.72 or 1.0
    Quire.overview_zoom = Quire.overview_zoom + (target_zoom - Quire.overview_zoom) * math.min(1.0, dt * 14.0)

    if Quire.scratchpad_hwnd and wm.is_window(Quire.scratchpad_hwnd) then
        local sp_w = math.floor(ww * 0.70)
        local sp_h = math.floor(wh * 0.60)
        local sp_x = wx + math.floor((ww - sp_w) * 0.5)
        local target_sp_y = Quire.scratchpad_visible and (wy + 24) or -(sp_h + 120)

        Quire.scratchpad_y, Quire.scratchpad_vy = solve_spring(Quire.scratchpad_y, Quire.scratchpad_vy, target_sp_y,
            sp.stiffness, sp.damping, sp.mass, dt)
        wm.move_window(Quire.scratchpad_hwnd, sp_x, math.floor(Quire.scratchpad_y), sp_w, sp_h)

        if not Quire.scratchpad_visible and Quire.scratchpad_y < -(sp_h + 80) then
            wm.cloak_window(Quire.scratchpad_hwnd, true)
        end
    end

    local mid_x = wx + math.floor(ww * 0.5)
    local mid_y = wy + math.floor(wh * 0.5)

    for _, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col.windows) do
            if not Quire.closing_windows[hwnd] and not Quire.transferring_windows[hwnd] then
                local target = Quire.window_targets[hwnd]
                if target then
                    local curr = Quire.window_currents[hwnd]
                    local screen_target_x = target.world_x - cam_floor_x
                    local screen_target_y = target.y + cam_floor_y

                    if not curr then
                        curr = {
                            world_x = target.world_x,
                            world_y = target.y,
                            x = screen_target_x,
                            y = screen_target_y,
                            w = target.w,
                            h = target.h,
                            vx = 0,
                            vy = 0,
                            vw = 0,
                            vh = 0,
                            needs_sync = true
                        }
                        Quire.window_currents[hwnd] = curr
                        wm.move_window(hwnd, curr.x, curr.y, curr.w, curr.h)
                    else
                        curr.world_x, curr.vx = solve_spring(curr.world_x or target.world_x, curr.vx or 0,
                            target.world_x, sp.stiffness, sp.damping, sp.mass, dt)
                        curr.world_y, curr.vy = solve_spring(curr.world_y or target.y, curr.vy or 0, target.y,
                            sp.stiffness, sp.damping, sp.mass, dt)
                        curr.w, curr.vw = solve_spring(curr.w, curr.vw, target.w, sp.stiffness, sp.damping, sp.mass, dt)
                        curr.h, curr.vh = solve_spring(curr.h, curr.vh, target.h, sp.stiffness, sp.damping, sp.mass, dt)

                        local norm_x = math.floor(curr.world_x) - cam_floor_x
                        local norm_y = math.floor(curr.world_y) + cam_floor_y
                        local norm_w = math.floor(curr.w)
                        local norm_h = math.floor(curr.h)

                        local final_x, final_y, final_w, final_h = norm_x, norm_y, norm_w, norm_h

                        if Quire.overview_zoom < 0.998 then
                            local rel_cx = (norm_x + norm_w * 0.5) - mid_x
                            local rel_cy = (norm_y + norm_h * 0.5) - mid_y
                            final_w = math.max(10, math.floor(norm_w * Quire.overview_zoom))
                            final_h = math.max(10, math.floor(norm_h * Quire.overview_zoom))
                            final_x = math.floor(mid_x + (rel_cx * Quire.overview_zoom) - (final_w * 0.5))
                            final_y = math.floor(mid_y + (rel_cy * Quire.overview_zoom) - (final_h * 0.5))
                        end

                        curr.x = final_x
                        curr.y = final_y
                        curr.render_w = final_w
                        curr.render_h = final_h

                        local changed = (curr.ax ~= final_x or curr.ay ~= final_y or curr.aw ~= final_w or curr.ah ~=
                                            final_h)
                        if (changed or curr.needs_sync) and final_x > -final_w - 100 and final_x < sw + 100 then
                            wm.move_window(hwnd, final_x, final_y, final_w, final_h)
                            curr.ax, curr.ay, curr.aw, curr.ah = final_x, final_y, final_w, final_h
                            curr.needs_sync = false
                        end
                    end
                end
            end
        end
    end

    local fg = wm.get_foreground_window()
    local fg_covers_screen = false
    if fg and fg ~= 0 then
        local fx, fy, fw, fh = wm.get_window_rect(fg)
        if fx <= 2 and fy <= 2 and fw >= sw - 4 and fh >= sh - 4 then
            local is_our_tiled = false
            for _, col in ipairs(ws.columns) do
                for _, hwnd in ipairs(col.windows) do
                    if hwnd == fg then
                        is_our_tiled = true
                        break
                    end
                end
            end
            if not is_our_tiled then
                fg_covers_screen = true
            end
        end
    end

    if not fg_covers_screen then
        local is_smart = cfg.smart_gaps and (#ws.columns == 1 and #ws.columns[1].windows == 1) and
                             not Quire.overview_active
        local win_rounding = is_smart and 0 or math.floor(cfg.rounding * Quire.overview_zoom)
        local border_thickness = (is_smart and cfg.smart_borders) and 0 or cfg.border_size

        for _, col in ipairs(ws.columns) do
            for _, hwnd in ipairs(col.windows) do
                if not Quire.closing_windows[hwnd] and not Quire.transferring_windows[hwnd] then
                    local curr = Quire.window_currents[hwnd]
                    if curr and curr.x > -curr.w and curr.x < sw then
                        local is_active = (hwnd == Quire.focused_window) and (fg == hwnd)
                        local bx = curr.x
                        local by = curr.y
                        local bw = curr.render_w or curr.w
                        local bh = curr.render_h or curr.h

                        local handled = false
                        if Quire.hooks.on_draw_window_border then
                            local win_ctx = {
                                hwnd = hwnd,
                                x = bx,
                                y = by,
                                w = bw,
                                h = bh,
                                active = is_active,
                                time = now,
                                title = wm.get_window_title(hwnd),
                                class = wm.get_class_name(hwnd),
                                process = wm.get_process_name and wm.get_process_name(hwnd) or "",
                                rounding = win_rounding,
                                thickness = border_thickness
                            }
                            local ok, res = pcall(Quire.hooks.on_draw_window_border, win_ctx)
                            if ok and res == true then
                                handled = true
                            end
                        end

                        if not handled and border_thickness > 0 then
                            local col_color = is_active and cfg.border_active or cfg.border_inactive
                            local offset_x, offset_y = 0, 0
                            if is_active and anims.idle[cfg.idle_mode] then
                                col_color, offset_x, offset_y = anims.idle[cfg.idle_mode](now, col_color)
                            end

                            if is_active and ui.draw_glow_rounded_rect then
                                ui.draw_glow_rounded_rect(bx + offset_x, by + offset_y, bw, bh, win_rounding,
                                    col_color[1], col_color[2], col_color[3], col_color[4] or 1.0, 1.0, 3.0)
                            end

                            ui.draw_rounded_rect(bx + offset_x, by + offset_y, bw, bh, win_rounding, col_color[1],
                                col_color[2], col_color[3], col_color[4] or 1.0, border_thickness)
                        end
                    end
                end
            end
        end
    end

    if Quire.hooks.on_draw_hud then
        local hud_ctx = {
            workspace = Quire.current_workspace,
            focused = Quire.focused_window,
            work_area = {
                x = wx,
                y = wy,
                w = ww,
                h = wh
            },
            screen = {
                w = sw,
                h = sh
            },
            time = now
        }
        local ok, err = pcall(Quire.hooks.on_draw_hud, hud_ctx)
        if not ok then
            log("HUD hook error: " .. tostring(err))
        end
    else
        if cfg.enable_minimap ~= false then
            minimap.update(dt)
            minimap.draw(camera_x)
        end
    end

    if Quire.hooks.on_post_render then
        pcall(Quire.hooks.on_post_render, now, sw, sh)
    end
    if cfg.enable_isle ~= false then
        isle.update(now, dt)
        isle.draw(now)
    end
    alttab.draw()
    launcher.draw(1.0)
end

Quire.on_alttab_action = function(action_type)
    alttab.action(action_type)
end

function Quire.toggle_launcher()
    launcher.toggle()
    if wm.set_input_capture then
        wm.set_input_capture(Quire.launcher_active)
    end
end

local function recheck_tiled_windows()
    local ws = get_ws(Quire.current_workspace)
    local to_float = {}

    for col_idx, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col.windows) do
            local title = wm.get_window_title(hwnd)
            local class = wm.get_class_name(hwnd)
            for _, pattern in ipairs(Quire.window_rules.float) do
                local p = pattern:lower()
                local proc = (wm.get_process_name and wm.get_process_name(hwnd) or ""):lower()
                if proc:find(p, 1, true) or (title and title:lower():find(p, 1, true)) or
                    (class and class:lower():find(p, 1, true)) then
                    table.insert(to_float, hwnd)
                    break
                end
            end
        end
    end

    for _, hwnd in ipairs(to_float) do
        local col_idx, row_idx = Quire.find_window_pos(hwnd)
        if col_idx then
            table.remove(ws.columns[col_idx].windows, row_idx)
            if #ws.columns[col_idx].windows == 0 then
                table.remove(ws.columns, col_idx)
            end
            Quire.floating_windows[hwnd] = true
            local wx, wy, ww, wh = wm.get_work_area()
            local fw = math.floor(ww * 0.60)
            local fh = math.floor(wh * 0.70)
            local fx = wx + math.floor((ww - fw) / 2)
            local fy = wy + math.floor((wh - fh) / 2)
            Quire.floating_rects[hwnd] = {fx, fy, fw, fh}
            wm.move_window(hwnd, fx, fy, fw, fh)
        end
    end
end

Quire.reload_config = function()
    local config_path = wm.get_config_path()
    local fn, load_err = loadfile(config_path)
    if not fn then
        log("CONFIG FILE ERROR: " .. tostring(load_err))
        return
    end

    wm.unregister_all_hotkeys()
    Quire.hotkeys = {}
    hotkey_counter = 1
    Quire.window_rules.float = {}

    local ok, run_err = pcall(fn)
    if ok then
        if Quire.config.border_active then
            Quire.theme.active_border_color = Quire.config.border_active
            Quire.theme.accent_color = Quire.config.border_active
        end
        if Quire.config.border_inactive then
            Quire.theme.border_color = Quire.config.border_inactive
        end
        if Quire.config.rounding then
            Quire.theme.rounding = Quire.config.rounding
        end
        recheck_tiled_windows()
        log("Config reloaded successfully!")
        trigger_hud()
        Quire.retile()
    else
        log("CONFIG RUNTIME ERROR: " .. tostring(run_err))
    end
end

local vert_scroll_accum = 0.0
local last_scroll_time = 0.0

Quire.on_trackpad_scroll = function(dx, dy, ctrl_down, alt_down)
    local now = get_wall_time()

    if (ctrl_down and alt_down) or ctrl_down then
        if (now - last_scroll_time) > 0.35 then
            vert_scroll_accum = 0.0
        end
        last_scroll_time = now

        local delta = (dy ~= 0.0) and dy or dx
        vert_scroll_accum = vert_scroll_accum + delta

        if vert_scroll_accum >= 80.0 then
            Quire.cycle_workspace(-1)
            vert_scroll_accum = 0.0
            return true
        elseif vert_scroll_accum <= -80.0 then
            Quire.cycle_workspace(1)
            vert_scroll_accum = 0.0
            return true
        end
        return true
    end

    vert_scroll_accum = 0.0

    local wx, wy, ww, wh = wm.get_work_area()
    local cfg = Quire.config
    local total_w = layout_columns(Quire.current_workspace, wx, wy, ww, wh, cfg)
    local max_cam_x = math.max(0, (total_w - cfg.gaps_in + cfg.gaps_out - wx) - ww)

    if Quire.overview_active then
        local scroll_step = (math.abs(dx) > 0.01) and dx or -dy
        local speed = cfg.trackpad_speed or 1.2
        camera_target_x = math.max(0, math.min(max_cam_x, camera_target_x + (scroll_step * speed)))
        Quire.scroll_active_until = now + 0.20
        Quire.is_touch_scrolling = true
        for _, c in pairs(Quire.window_currents) do
            c.needs_sync = true
        end
        return true
    end

    if math.abs(dx) < 0.01 then
        return false
    end

    local speed = cfg.trackpad_speed or 1.2
    camera_target_x = math.max(0, math.min(max_cam_x, camera_target_x + (dx * speed)))
    Quire.scroll_active_until = now + 0.16
    Quire.is_touch_scrolling = true

    for _, c in pairs(Quire.window_currents) do
        c.needs_sync = true
    end

    return true
end

Quire.on_ipc_request = function(req)
    if not req or req == "" then
        return "ERROR: Empty command"
    end
    local parts = {}
    for part in req:gmatch("%S+") do
        table.insert(parts, part)
    end
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
    elseif cmd == "reload" then
        Quire.reload_config()
        return "OK"
    elseif cmd == "close" then
        if Quire.focused_window then
            Quire.safe_close_window(Quire.focused_window)
        end
        return "OK"
    elseif cmd == "clients" then
        local out = {}
        for ws_id, ws in pairs(Quire.workspaces) do
            for c_i, col in ipairs(ws.columns) do
                for r_i, hwnd in ipairs(col.windows) do
                    table.insert(out, string.format("WS:%d Col:%d Row:%d [0x%X] %s", ws_id, c_i, r_i, hwnd,
                        wm.get_window_title(hwnd)))
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
    for part in string.gmatch(combo, "[^+%s]+") do
        table.insert(parts, part:upper())
    end
    local mod, vk = 0, 0
    for i = 1, #parts - 1 do
        local p = parts[i]
        if p == "SUPER" or p == "WIN" then
            mod = mod + 0x0008
        elseif p == "SHIFT" then
            mod = mod + 0x0004
        elseif p == "CTRL" or p == "CONTROL" then
            mod = mod + 0x0002
        elseif p == "ALT" then
            mod = mod + 0x0001
        end
    end
    local key = parts[#parts]
    if #key == 1 then
        vk = string.byte(key)
    else
        local special = {
            ["LEFT"] = 0x25,
            ["UP"] = 0x26,
            ["RIGHT"] = 0x27,
            ["DOWN"] = 0x28,
            ["RETURN"] = 0x0D,
            ["ENTER"] = 0x0D,
            ["SPACE"] = 0x20,
            ["TAB"] = 0x09,
            ["ESCAPE"] = 0x1B,
            ["GRAVE"] = 0xC0,
            ["`"] = 0xC0,
            ["~"] = 0xC0,
            ["MINUS"] = 0xBD,
            ["EQUAL"] = 0xBB,
            ["BRACKETLEFT"] = 0xDB,
            ["["] = 0xDB,
            ["BRACKETRIGHT"] = 0xDD,
            ["]"] = 0xDD,
            ["COMMA"] = 0xBC,
            ["PERIOD"] = 0xBE,
            ["SLASH"] = 0xBF,
            ["SEMICOLON"] = 0xBA
        }
        vk = special[key] or 0
    end
    return mod, vk
end

function Quire.bind(combo, callback)
    local mod, vk = parse_combo(combo)
    if vk == 0 then
        return
    end
    local id = hotkey_counter
    hotkey_counter = hotkey_counter + 1
    Quire.hotkeys[id] = callback
    wm.register_hotkey(id, mod, vk)
end

Quire.on_hotkey = function(id)
    if Quire.hotkeys[id] then
        Quire.hotkeys[id]()
    end
end

local config_path = wm.get_config_path()
local fn, load_err = loadfile(config_path)
if not fn then
    log("Registering default Quire binds...")
    Quire.bind("Alt+H", function()
        Quire.focus_direction("left")
    end)
    Quire.bind("Alt+L", function()
        Quire.focus_direction("right")
    end)
    Quire.bind("Alt+K", function()
        Quire.focus_direction("up")
    end)
    Quire.bind("Alt+J", function()
        Quire.focus_direction("down")
    end)
    Quire.bind("Alt+Shift+H", function()
        Quire.move_column("left")
    end)
    Quire.bind("Alt+Shift+L", function()
        Quire.move_column("right")
    end)
    Quire.bind("Alt+Q", function()
        Quire.cycle_workspace(-1)
    end)
    Quire.bind("Alt+E", function()
        Quire.cycle_workspace(1)
    end)
    Quire.bind("Alt+Ctrl+H", function()
        Quire.move_window_to_monitor("left")
    end)
    Quire.bind("Alt+Ctrl+L", function()
        Quire.move_window_to_monitor("right")
    end)
    Quire.bind("Win+Ctrl+Left", function()
        Quire.focus_direction("left")
    end)
    Quire.bind("Win+Ctrl+Right", function()
        Quire.focus_direction("right")
    end)
    Quire.bind("Win+Ctrl+Up", function()
        Quire.cycle_workspace(-1)
    end)
    Quire.bind("Win+Ctrl+Down", function()
        Quire.cycle_workspace(1)
    end)
    Quire.bind("Ctrl+Alt+Left", function()
        Quire.focus_direction("left")
    end)
    Quire.bind("Ctrl+Alt+Right", function()
        Quire.focus_direction("right")
    end)
    Quire.bind("Ctrl+Alt+Up", function()
        Quire.cycle_workspace(-1)
    end)
    Quire.bind("Ctrl+Alt+Down", function()
        Quire.cycle_workspace(1)
    end)
    Quire.bind("Alt+O", Quire.toggle_overview)
    Quire.bind("Alt+Grave", Quire.toggle_scratchpad)
    Quire.bind("Alt+Shift+Grave", Quire.mark_scratchpad)
    Quire.bind("Alt+F", Quire.toggle_fullscreen)
    Quire.bind("Alt+V", Quire.toggle_floating)
    Quire.bind("Alt+D", Quire.cycle_column_preset)
    Quire.bind("Alt+Shift+S", Quire.save_session)
    Quire.bind("Alt+Shift+R", Quire.restore_session)
    Quire.bind("Alt+Space", Quire.toggle_launcher)
    Quire.bind("Alt+Return", launcher.commit)
    for i = 1, 9 do
        Quire.bind("Alt+" .. i, function()
            Quire.switch_workspace(i)
        end)
        Quire.bind("Alt+Shift+" .. i, function()
            Quire.move_to_workspace(i)
        end)
    end
else
    local ok, run_err = pcall(fn)
    if not ok then
        log("CONFIG RUNTIME ERROR: " .. tostring(run_err))
    end
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
                windows = {hwnd}
            })
            Quire.window_ws[hwnd] = 1
            if wm.track_window then
                wm.track_window(hwnd)
            end
        else
            if wm.track_window then
                wm.track_window(hwnd)
            end
        end
    end
end

if #ws1.columns > 0 and #ws1.columns[1].windows > 0 then
    Quire.focused_window = ws1.columns[1].windows[1]
    if alttab and alttab.record_focus then
        alttab.record_focus(Quire.focused_window)
    end
end

function Quire.cleanup_for_exit()
    local wx, wy, ww, wh = wm.get_work_area()
    local off = 0

    for ws_id, ws in pairs(Quire.workspaces) do
        for _, col in ipairs(ws.columns) do
            for _, hwnd in ipairs(col.windows) do
                if wm.is_window(hwnd) then
                    wm.cloak_window(hwnd, false)
                    if wm.set_topmost then
                        wm.set_topmost(hwnd, false)
                    end
                    local rx, ry, rw, rh = wm.get_window_rect(hwnd)
                    if not rx or rx < -100 or ry < -100 or rx > ww + 100 or ry > wh + 100 or rw < 150 or rh < 100 then
                        wm.move_window(hwnd, wx + 60 + off, wy + 60 + off, math.floor(ww * 0.7), math.floor(wh * 0.7))
                        off = (off + 35) % 350
                    end
                end
            end
        end
    end

    if Quire.scratchpad_hwnd and wm.is_window(Quire.scratchpad_hwnd) then
        wm.cloak_window(Quire.scratchpad_hwnd, false)
        if wm.set_topmost then
            wm.set_topmost(Quire.scratchpad_hwnd, false)
        end
        wm.move_window(Quire.scratchpad_hwnd, wx + 80, wy + 80, math.floor(ww * 0.7), math.floor(wh * 0.7))
    end

    for hwnd, _ in pairs(Quire.floating_windows) do
        if wm.is_window(hwnd) then
            wm.cloak_window(hwnd, false)
            if wm.set_topmost then
                wm.set_topmost(hwnd, false)
            end
        end
    end
end

if Quire.autostart and type(Quire.autostart) == "table" then
    for _, app_cmd in ipairs(Quire.autostart) do
        if type(app_cmd) == "string" and app_cmd ~= "" then
            wm.spawn(app_cmd)
        end
    end
end

isle.init()

Quire.retile()
