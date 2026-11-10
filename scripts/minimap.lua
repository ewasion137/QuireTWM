local minimap = {}

local state = {
    timer = 0.0,
    alpha = 0.0,
    valpha = 0.0,
    x = 0.0,
    y = 0.0,
    w = 0.0,
    h = 66.0,
    cols_layout = {}
}

local function solve_spring(curr, vel, target, stiffness, damping, mass, dt)
    if dt <= 0.0 then return curr, vel end
    local diff = curr - target
    if math.abs(diff) < 0.01 and math.abs(vel) < 0.01 then return target, 0.0 end
    dt = math.min(dt, 0.033)
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
        return target + decay * (c1 + c2 * dt), decay * (vel - (c1 + c2 * dt) * omega0 + c2)
    end
end

function minimap.trigger(duration)
    state.timer = duration or 1.4
end

function minimap.update(dt)
    if state.timer > 0.0 then
        state.timer = state.timer - dt
    end
    local target_alpha = (state.timer > 0.0) and 1.0 or 0.0
    state.alpha, state.valpha = solve_spring(state.alpha, state.valpha, target_alpha, 240, 24, 1.0, dt)
end

function minimap.on_mouse_down(mx, my)
    if state.alpha < 0.1 then
        return false
    end

    if mx >= state.x and mx <= (state.x + state.w) and my >= state.y and my <= (state.y + state.h) then
        for _, col in ipairs(state.cols_layout) do
            if mx >= col.x and mx <= (col.x + col.w) and my >= col.y and my <= (col.y + col.h) then
                if col.hwnd and wm.is_window(col.hwnd) then
                    Quire.focused_window = col.hwnd
                    wm.focus_window(col.hwnd)
                    Quire.retile()
                    state.timer = 1.4
                    return true
                end
            end
        end
        return true
    end
    return false
end

function minimap.draw(camera_x)
    if state.alpha < 0.01 then
        return
    end

    local ws = Quire.workspaces[Quire.current_workspace]
    if not ws or not ws.columns or #ws.columns == 0 then
        return
    end

    local sw, sh = wm.get_screen_size()
    local wx, wy, ww, wh = wm.get_work_area()
    local t = Quire.theme
    local cfg = Quire.config
    local accent = cfg.border_active or t.active_border_color
    local a = state.alpha

    local num_cols = #ws.columns
    local panel_w = math.max(260.0, math.min(sw * 0.55, 110.0 + num_cols * 65.0))
    local panel_h = state.h
    local panel_x = wx + math.floor((ww - panel_w) * 0.5)
    local panel_y = wy + wh - panel_h - 18.0

    state.x = panel_x
    state.y = panel_y
    state.w = panel_w

    if ui.draw_shadow_rounded_rect then
        ui.draw_shadow_rounded_rect(panel_x, panel_y, panel_w, panel_h, 14.0, 0.0, 0.0, 0.0, 0.65 * a, 14.0, 2.0)
    end

    ui.fill_rounded_rect(panel_x, panel_y, panel_w, panel_h, 14.0, 0.04, 0.05, 0.07, 0.94 * a)
    ui.draw_rounded_rect(panel_x, panel_y, panel_w, panel_h, 14.0, 0.20, 0.22, 0.28, 0.45 * a, 1.0)

    local header_text = string.format("WS %d  |  %d COLUMNS", Quire.current_workspace, num_cols)
    ui.draw_text(header_text, panel_x + 16, panel_y + 8, 9, 0.60, 0.64, 0.72, 0.9 * a, t.font_family)

    local cur_ratio_str = "100%"
    if Quire.focused_window then
        local c = Quire.find_window_pos(Quire.focused_window)
        if c and ws.columns[c] and ws.columns[c].width then
            cur_ratio_str = math.floor(ws.columns[c].width * 100) .. "%"
        end
    end
    local rw_text = ui.measure_text(cur_ratio_str, 9, t.font_family)
    ui.draw_text(cur_ratio_str, panel_x + panel_w - rw_text - 16, panel_y + 8, 9, accent[1], accent[2], accent[3], a, t.font_family)

    local inner_margin_x = 16.0
    local inner_margin_top = 24.0
    local inner_x = panel_x + inner_margin_x
    local inner_y = panel_y + inner_margin_top
    local inner_w = panel_w - (inner_margin_x * 2.0)
    local inner_h = panel_h - inner_margin_top - 10.0

    local avail_w = ww - (cfg.gaps_out * 2)
    local total_world_w = 0
    for _, col in ipairs(ws.columns) do
        local col_w = math.floor(avail_w * (col.width or cfg.default_column_width))
        total_world_w = total_world_w + col_w + cfg.gaps_in
    end
    total_world_w = math.max(ww, total_world_w)

    local scale = inner_w / total_world_w
    state.cols_layout = {}

    local cur_col_world_x = 0
    for c_idx, col in ipairs(ws.columns) do
        local col_w = math.floor(avail_w * (col.width or cfg.default_column_width))
        local mc_x = inner_x + math.floor(cur_col_world_x * scale)
        local mc_w = math.max(6.0, math.floor(col_w * scale))
        local num_wins = #col.windows

        if num_wins > 0 then
            local win_h_total = inner_h - ((num_wins - 1) * 2.0)
            local each_h = math.floor(win_h_total / num_wins)

            for w_idx, hwnd in ipairs(col.windows) do
                local mw_y = inner_y + (w_idx - 1) * (each_h + 2.0)
                local mw_h = (w_idx == num_wins) and (inner_y + inner_h - mw_y) or each_h
                local is_active = (hwnd == Quire.focused_window)

                if is_active then
                    ui.fill_rounded_rect(mc_x, mw_y, mc_w, mw_h, 3.0, accent[1], accent[2], accent[3], 0.85 * a)
                    ui.draw_rounded_rect(mc_x, mw_y, mc_w, mw_h, 3.0, 1.0, 1.0, 1.0, 0.9 * a, 1.0)
                else
                    ui.fill_rounded_rect(mc_x, mw_y, mc_w, mw_h, 3.0, 0.12, 0.14, 0.18, 0.75 * a)
                    ui.draw_rounded_rect(mc_x, mw_y, mc_w, mw_h, 3.0, 0.22, 0.25, 0.32, 0.4 * a, 1.0)
                end

                table.insert(state.cols_layout, {
                    x = mc_x,
                    y = mw_y,
                    w = mc_w,
                    h = mw_h,
                    hwnd = hwnd
                })
            end
        end

        cur_col_world_x = cur_col_world_x + col_w + cfg.gaps_in
    end

    local cam_x_clamped = math.max(0.0, camera_x)
    local vp_x = inner_x + math.floor(cam_x_clamped * scale)
    local vp_w = math.max(24.0, math.floor(ww * scale))
    local vp_y = inner_y - 2.0
    local vp_h = inner_h + 4.0

    ui.fill_rounded_rect(vp_x, vp_y, vp_w, vp_h, 4.0, accent[1], accent[2], accent[3], 0.12 * a)
    ui.draw_rounded_rect(vp_x, vp_y, vp_w, vp_h, 4.0, accent[1], accent[2], accent[3], 0.85 * a, 1.5)
end

return minimap