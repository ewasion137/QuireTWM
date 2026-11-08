local isle = {}

local state = {
    mode = "compact",
    w = 320.0,
    h = 30.0,
    target_w = 320.0,
    target_h = 30.0,
    vw = 0.0,
    vh = 0.0,
    x = 0.0,
    y = 0.0,
    is_hovered = false,
    
    last_volume = -1.0,
    popup_timer = 0.0,
    popup_type = nil,
    last_track = "",
    
    stopwatch_active = false,
    stopwatch_time = 0.0,
    timer_active = false,
    timer_time = 1500.0,
    timer_total = 1500.0,
    clock_mode = "stopwatch",
    
    note_text = "",
    note_active = false,
    
    cached_cpu = 0,
    cached_ram = 0,
    cached_battery = { percentage = -1, is_charging = false, has_battery = false },
    last_stat_time = 0.0,
    
    wave_anim = 0.0
}

local function solve_spring(curr, vel, target, stiffness, damping, mass, dt)
    if dt <= 0.0 then return curr, vel end
    local diff = curr - target
    if math.abs(diff) < 0.1 and math.abs(vel) < 0.1 then return target, 0.0 end
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

function isle.init()
    local note_path = wm.get_config_path():gsub("config%.lua$", "notes.txt")
    local f = io.open(note_path, "r")
    if f then
        state.note_text = f:read("*a") or ""
        f:close()
    end
    if state.note_text == "" then
        state.note_text = "Todo: clean up desk, review pull request"
    end
    state.last_volume = wm.get_volume and wm.get_volume() or 0.5
end

local function save_note()
    local note_path = wm.get_config_path():gsub("config%.lua$", "notes.txt")
    local f = io.open(note_path, "w")
    if f then
        f:write(state.note_text)
        f:close()
    end
end

function isle.update(now, dt)
    state.wave_anim = state.wave_anim + dt * 5.0

    if now - state.last_stat_time > 1.0 then
        state.last_stat_time = now
        if wm.get_cpu_usage then state.cached_cpu = math.floor(wm.get_cpu_usage()) end
        if wm.get_ram_usage then state.cached_ram = wm.get_ram_usage() end
        if wm.get_battery then state.cached_battery = wm.get_battery() end
    end

    if wm.get_volume then
        local v = wm.get_volume()
        if state.last_volume >= 0.0 and math.abs(v - state.last_volume) > 0.015 then
            state.popup_timer = 1.8
            state.popup_type = "volume"
        end
        state.last_volume = v
    end

    if wm.get_media_title then
        local t = wm.get_media_title()
        if t ~= "" and t ~= state.last_track then
            state.last_track = t
            state.popup_timer = 2.4
            state.popup_type = "media"
        end
    end

    if state.popup_timer > 0 then
        state.popup_timer = state.popup_timer - dt
    end

    if state.stopwatch_active then
        state.stopwatch_time = state.stopwatch_time + dt
    end

    if state.timer_active then
        state.timer_time = math.max(0.0, state.timer_time - dt)
        if state.timer_time <= 0.0 then
            state.timer_active = false
            state.popup_timer = 3.0
            state.popup_type = "timer_done"
        end
    end

    if state.is_hovered then
        state.target_w = 420.0
        state.target_h = 176.0
    elseif state.popup_timer > 0 then
        if state.popup_type == "volume" then
            state.target_w = 260.0
            state.target_h = 36.0
        else
            state.target_w = 380.0
            state.target_h = 36.0
        end
    else
        state.target_w = 320.0
        state.target_h = 30.0
    end

    state.w, state.vw = solve_spring(state.w, state.vw, state.target_w, 240, 24, 1.0, dt)
    state.h, state.vh = solve_spring(state.h, state.vh, state.target_h, 240, 24, 1.0, dt)
end

function isle.update_mouse(mx, my)
    local is_in = mx >= state.x and mx <= (state.x + state.w) and my >= state.y and my <= (state.y + state.h)
    state.is_hovered = is_in
end

function isle.on_mouse_down(mx, my)
    if not (mx >= state.x and mx <= (state.x + state.w) and my >= state.y and my <= (state.y + state.h)) then
        if state.note_active then
            state.note_active = false
            save_note()
        end
        return false
    end

    if not state.is_hovered or state.h < 120 then
        return true
    end

    local py = state.y + 10
    if my >= py and my <= py + 34 then
        local btn_w = 32
        local bx = state.x + state.w - 110
        if mx >= bx and mx <= bx + btn_w then
            if wm.media_prev then wm.media_prev() end
            return true
        elseif mx >= bx + 34 and mx <= bx + 34 + btn_w then
            if wm.media_play_pause then wm.media_play_pause() end
            return true
        elseif mx >= bx + 68 and mx <= bx + 68 + btn_w then
            if wm.media_next then wm.media_next() end
            return true
        end
    end

    local cy = state.y + 54
    if my >= cy and my <= cy + 32 then
        local toggle_x = state.x + 12
        if mx >= toggle_x and mx <= toggle_x + 80 then
            state.clock_mode = (state.clock_mode == "stopwatch") and "timer" or "stopwatch"
            return true
        end

        local start_x = state.x + state.w - 130
        if mx >= start_x and mx <= start_x + 58 then
            if state.clock_mode == "stopwatch" then
                state.stopwatch_active = not state.stopwatch_active
            else
                state.timer_active = not state.timer_active
            end
            return true
        end

        local reset_x = start_x + 64
        if mx >= reset_x and mx <= reset_x + 54 then
            if state.clock_mode == "stopwatch" then
                state.stopwatch_active = false
                state.stopwatch_time = 0.0
            else
                state.timer_active = false
                state.timer_time = state.timer_total
            end
            return true
        end
    end

    local ny = state.y + 96
    if my >= ny and my <= state.y + state.h - 10 then
        state.note_active = true
        return true
    end

    return true
end

function isle.on_keyboard_input(vk, char)
    if not state.note_active then
        return false
    end

    if vk == 0x1B or vk == 0x0D then
        state.note_active = false
        save_note()
        return true
    end

    if vk == 0x08 then
        if #state.note_text > 0 then
            local len = utf8.len(state.note_text)
            if len and len > 0 then
                local offset = utf8.offset(state.note_text, len)
                if offset then
                    state.note_text = state.note_text:sub(1, offset - 1)
                else
                    state.note_text = state.note_text:sub(1, -2)
                end
            else
                state.note_text = ""
            end
        end
        return true
    end

    if char and #char > 0 then
        local b = char:byte(1)
        if b >= 32 and #state.note_text < 120 then
            state.note_text = state.note_text .. char
            return true
        end
    end

    return false
end

local function format_time(sec)
    local m = math.floor(sec / 60)
    local s = math.floor(sec % 60)
    return string.format("%02d:%02d", m, s)
end

function isle.draw()
    local sw = wm.get_screen_size()
    local wx, wy = wm.get_work_area()
    local t = Quire.theme
    local accent = Quire.config.border_active or t.active_border_color

    state.x = wx + math.floor((sw - state.w) * 0.5)
    state.y = wy + 6

    local ix = state.x
    local iy = state.y
    local iw = state.w
    local ih = state.h
    local rad = math.min(16.0, ih * 0.5)

    if ui.draw_shadow_rounded_rect then
        ui.draw_shadow_rounded_rect(ix, iy, iw, ih, rad, 0.0, 0.0, 0.0, 0.65, 12.0, 2.0)
    end

    ui.fill_rounded_rect(ix, iy, iw, ih, rad, 0.05, 0.05, 0.07, 0.96)
    ui.draw_rounded_rect(ix, iy, iw, ih, rad, 0.22, 0.24, 0.30, 0.45, 1.0)

    if ih < 50 then
        if state.popup_timer > 0 and state.popup_type == "volume" then
            local vol = state.last_volume or 0.0
            ui.draw_text("VOL", ix + 14, iy + 10, 10, accent[1], accent[2], accent[3], 1.0, t.font_family)
            local bar_x = ix + 48
            local bar_y = iy + 13
            local bar_w = iw - 100
            ui.fill_rounded_rect(bar_x, bar_y, bar_w, 8, 4, 0.14, 0.16, 0.20, 0.9)
            ui.fill_rounded_rect(bar_x, bar_y, math.floor(bar_w * vol), 8, 4, accent[1], accent[2], accent[3], 1.0)
            ui.draw_text(math.floor(vol * 100) .. "%", bar_x + bar_w + 12, iy + 10, 10, 0.85, 0.88, 0.95, 1.0, t.font_family)
            return
        end

        local badge = "WS " .. tostring(Quire.current_workspace)
        ui.fill_rounded_rect(ix + 6, iy + 5, 42, 20, 6, 0.12, 0.14, 0.18, 0.9)
        ui.draw_text(badge, ix + 12, iy + 9, 9, accent[1], accent[2], accent[3], 1.0, t.font_family)

        local mid_text = ""
        local is_media = (state.last_track ~= "")
        if state.stopwatch_active then
            mid_text = "⏱ " .. format_time(state.stopwatch_time)
        elseif state.timer_active then
            mid_text = "⏳ " .. format_time(state.timer_time)
        elseif is_media then
            mid_text = state.last_track
        else
            mid_text = Quire.focused_window and wm.get_window_title(Quire.focused_window) or "QuireTWM"
        end

        if is_media and not state.stopwatch_active and not state.timer_active then
            local wx_bar = ix + 54
            for b = 1, 3 do
                local h_val = 4 + math.abs(math.sin(state.wave_anim + b * 1.4)) * 9
                ui.fill_rounded_rect(wx_bar + (b - 1) * 4, iy + 15 - math.floor(h_val * 0.5), 2, math.floor(h_val), 1,
                    accent[1], accent[2], accent[3], 1.0)
            end
        end

        local text_x = (is_media and not state.stopwatch_active and not state.timer_active) and (ix + 70) or (ix + 54)
        local max_w = iw - 160
        if ui.measure_text(mid_text, 10, t.font_family) > max_w then
            mid_text = mid_text:sub(1, 26) .. "..."
        end
        ui.draw_text(mid_text, text_x, iy + 9, 10, 0.88, 0.90, 0.95, 0.95, t.font_family)

        local stat_str = string.format("%d%% | %d%%", state.cached_cpu, state.cached_ram)
        local bat = state.cached_battery
        if bat.has_battery and bat.percentage >= 0 then
            stat_str = string.format("%d%%⚡ %s", bat.percentage, stat_str)
        end
        local sw_w = ui.measure_text(stat_str, 9, t.font_family)
        ui.draw_text(stat_str, ix + iw - sw_w - 12, iy + 9, 9, 0.55, 0.58, 0.65, 0.85, t.font_family)
        return
    end

    local track_title = (state.last_track ~= "") and state.last_track or "No active media session"
    if ui.measure_text(track_title, 11, t.font_family) > (iw - 140) then
        track_title = track_title:sub(1, 34) .. "..."
    end
    ui.draw_text(track_title, ix + 16, iy + 18, 11, 0.92, 0.94, 0.98, 1.0, t.font_family)

    local btn_y = iy + 14
    local bx = ix + iw - 110
    ui.fill_rounded_rect(bx, btn_y, 28, 22, 4, 0.14, 0.16, 0.22, 0.9)
    ui.draw_text("<<", bx + 7, btn_y + 5, 9, 0.85, 0.88, 0.95, 1.0, t.font_family)

    ui.fill_rounded_rect(bx + 34, btn_y, 28, 22, 4, accent[1], accent[2], accent[3], 0.25)
    ui.draw_text("||", bx + 43, btn_y + 5, 9, accent[1], accent[2], accent[3], 1.0, t.font_family)

    ui.fill_rounded_rect(bx + 68, btn_y, 28, 22, 4, 0.14, 0.16, 0.22, 0.9)
    ui.draw_text(">>", bx + 75, btn_y + 5, 9, 0.85, 0.88, 0.95, 1.0, t.font_family)

    ui.draw_line(ix + 12, iy + 46, ix + iw - 12, iy + 46, 0.18, 0.20, 0.26, 0.45, 1.0)

    local cy = iy + 56
    local is_sw = (state.clock_mode == "stopwatch")
    ui.fill_rounded_rect(ix + 16, cy, 74, 22, 4, 0.14, 0.16, 0.22, 0.9)
    ui.draw_text(is_sw and "Stopwatch" or "Pomodoro", ix + 22, cy + 5, 9, accent[1], accent[2], accent[3], 1.0, t.font_family)

    local time_str = is_sw and format_time(state.stopwatch_time) or format_time(state.timer_time)
    ui.draw_text(time_str, ix + 104, cy + 3, 13, 0.95, 0.95, 0.98, 1.0, t.font_family)

    local is_running = is_sw and state.stopwatch_active or state.timer_active
    local start_x = ix + iw - 120
    ui.fill_rounded_rect(start_x, cy, 52, 22, 4, is_running and 0.45 or 0.16, is_running and 0.15 or 0.35, 0.22, 0.9)
    ui.draw_text(is_running and "Pause" or "Start", start_x + 12, cy + 5, 9, 0.92, 0.95, 0.98, 1.0, t.font_family)

    ui.fill_rounded_rect(start_x + 58, cy, 46, 22, 4, 0.14, 0.16, 0.22, 0.9)
    ui.draw_text("Reset", start_x + 68, cy + 5, 9, 0.75, 0.78, 0.85, 1.0, t.font_family)

    ui.draw_line(ix + 12, iy + 90, ix + iw - 12, iy + 90, 0.18, 0.20, 0.26, 0.45, 1.0)

    local ny = iy + 100
    local note_h = ih - 110
    local is_editing = state.note_active
    ui.fill_rounded_rect(ix + 14, ny, iw - 28, note_h, 6, 0.08, 0.09, 0.12, 0.9)
    ui.draw_rounded_rect(ix + 14, ny, iw - 28, note_h, 6, accent[1], accent[2], accent[3], is_editing and 0.8 or 0.2, 1.0)

    local disp_note = state.note_text
    if is_editing and (math.floor(now * 2.5) % 2) == 0 then
        disp_note = disp_note .. "|"
    end
    if disp_note == "" then
        disp_note = "Click to write a quick note..."
    end
    ui.draw_text(disp_note, ix + 22, ny + 10, 10, is_editing and 0.98 or 0.65, 0.95, 0.98, 0.9, t.font_family)
end

return isle