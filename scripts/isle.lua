local isle = {}

local function get_now()
    return wm.get_time and wm.get_time() or os.clock()
end

local state = {
    active_tab = "media",
    w = 340.0,
    h = 32.0,
    target_w = 340.0,
    target_h = 32.0,
    vw = 0.0,
    vh = 0.0,
    x = 0.0,
    y = 0.0,
    is_hovered = false,
    is_pinned = false,
    now = 0.0,

    last_volume = 0.5,
    popup_timer = 0.0,
    popup_type = nil,
    last_track = "",

    clock_mode = "timer",
    stopwatch_running = false,
    stopwatch_base = 0.0,
    stopwatch_start_ts = 0.0,

    timer_running = false,
    timer_total = 1500.0,
    timer_remain = 1500.0,
    timer_end_ts = 0.0,

    note_text = "",
    note_active = false,
    note_all_selected = false,

    cached_cpu = 0,
    cached_ram = 0,
    cached_battery = {
        percentage = -1,
        is_charging = false,
        has_battery = false
    },
    last_stat_time = -10.0,

    wave_anim = 0.0
}

local function solve_spring(curr, vel, target, stiffness, damping, mass, dt)
    if dt <= 0.0 then
        return curr, vel
    end
    local diff = curr - target
    if math.abs(diff) < 0.1 and math.abs(vel) < 0.1 then
        return target, 0.0
    end
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
        state.note_text = "Click to write a quick note..."
    end
    if wm.get_volume then
        local v = wm.get_volume()
        state.last_volume = (v and v >= 0.0) and v or 0.5
    end
    if wm.get_cpu_usage then
        state.cached_cpu = math.floor(wm.get_cpu_usage())
    end
    if wm.get_ram_usage then
        state.cached_ram = wm.get_ram_usage()
    end
    if wm.get_battery then
        state.cached_battery = wm.get_battery()
    end
end

local function save_note()
    local note_path = wm.get_config_path():gsub("config%.lua$", "notes.txt")
    local f = io.open(note_path, "w")
    if f then
        f:write(state.note_text)
        f:close()
    end
end

local function format_time(sec)
    local s_clamped = math.max(0, math.floor(sec))
    local m = math.floor(s_clamped / 60)
    local s = s_clamped % 60
    return string.format("%02d:%02d", m, s)
end

local function get_current_stopwatch()
    if state.stopwatch_running then
        return state.stopwatch_base + (get_now() - state.stopwatch_start_ts)
    end
    return state.stopwatch_base
end

local function get_current_timer()
    if state.timer_running then
        return math.max(0.0, state.timer_end_ts - get_now())
    end
    return state.timer_remain
end

function isle.update(now, dt)
    state.now = now
    state.wave_anim = state.wave_anim + dt * 5.0

    if now - state.last_stat_time > 0.8 then
        if Quire.focused_window and wm.is_window(Quire.focused_window) then
            local p = wm.get_process_name and wm.get_process_name(Quire.focused_window) or ""
            local wt = wm.get_window_title(Quire.focused_window) or ""
            state.cached_win_info = (p ~= "") and (p .. " - " .. wt) or wt
        else
            state.cached_win_info = "Desktop"
        end

        state.last_stat_time = now
        if wm.get_cpu_usage then
            state.cached_cpu = math.floor(wm.get_cpu_usage())
        end
        if wm.get_ram_usage then
            state.cached_ram = wm.get_ram_usage()
        end
        if wm.get_battery then
            state.cached_battery = wm.get_battery()
        end
    end

    if wm.get_volume then
        local v = wm.get_volume()
        if v and v >= 0.0 then
            if math.abs(v - state.last_volume) > 0.015 then
                state.popup_timer = 1.8
                state.popup_type = "volume"
            end
            state.last_volume = v
        end
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

    if state.timer_running then
        if get_now() >= state.timer_end_ts then
            state.timer_running = false
            state.timer_remain = 0.0
            state.popup_timer = 4.0
            state.popup_type = "timer_done"
            if wm.play_bell then
                wm.play_bell()
            end
        end
    end

    if state.is_hovered or state.is_pinned then
        state.target_w = 460.0
        state.target_h = 210.0
    elseif state.popup_timer > 0 then
        if state.popup_type == "volume" then
            state.target_w = 280.0
            state.target_h = 36.0
        else
            state.target_w = 400.0
            state.target_h = 36.0
        end
    else
        state.target_w = 340.0
        state.target_h = 32.0
    end

    state.w, state.vw = solve_spring(state.w, state.vw, state.target_w, 240, 24, 1.0, dt)
    state.h, state.vh = solve_spring(state.h, state.vh, state.target_h, 240, 24, 1.0, dt)
end

function isle.update_mouse(mx, my)
    local is_in = mx >= state.x and mx <= (state.x + state.w) and my >= state.y and my <= (state.y + state.h)
    state.is_hovered = is_in
end

function isle.on_mouse_down(mx, my)
    local is_hit = (mx >= state.x and mx <= (state.x + state.w) and my >= state.y and my <= (state.y + state.h))

    if not is_hit then
        if state.note_active then
            state.note_active = false
            state.note_all_selected = false
            if wm.set_input_capture then
                wm.set_input_capture(false)
            end
            save_note()
        end
        if state.is_pinned then
            state.is_pinned = false
        end
        return false
    end

    if state.h < 70 then
        state.is_pinned = not state.is_pinned
        return true
    end

    local tab_y = state.y + 12
    if my >= tab_y and my <= tab_y + 26 then
        local tabs = {"media", "timer", "notes", "system"}
        local tab_w = (state.w - 28) / #tabs
        for i, tname in ipairs(tabs) do
            local tx = state.x + 14 + (i - 1) * tab_w
            if mx >= tx and mx <= tx + tab_w then
                state.active_tab = tname
                if tname ~= "notes" and state.note_active then
                    state.note_active = false
                    state.note_all_selected = false
                    if wm.set_input_capture then
                        wm.set_input_capture(false)
                    end
                    save_note()
                end
                return true
            end
        end
    end

    if state.active_tab == "media" then
        local py = state.y + 60
        if my >= py and my <= py + 34 then
            local bx = state.x + state.w - 120
            if mx >= bx and mx <= bx + 32 then
                if wm.media_prev then
                    wm.media_prev()
                end
                return true
            elseif mx >= bx + 36 and mx <= bx + 68 then
                if wm.media_play_pause then
                    wm.media_play_pause()
                end
                return true
            elseif mx >= bx + 72 and mx <= bx + 104 then
                if wm.media_next then
                    wm.media_next()
                end
                return true
            end
        end

        local vy = state.y + 120
        if my >= vy and my <= vy + 28 then
            if mx >= state.x + 20 and mx <= state.x + 50 then
                if wm.set_volume then
                    wm.set_volume(math.max(0.0, state.last_volume - 0.05))
                end
                return true
            elseif mx >= state.x + state.w - 50 and mx <= state.x + state.w - 20 then
                if wm.set_volume then
                    wm.set_volume(math.min(1.0, state.last_volume + 0.05))
                end
                return true
            end
            local bar_x = state.x + 56
            local bar_w = state.w - 112
            if mx >= bar_x and mx <= bar_x + bar_w then
                local pct = (mx - bar_x) / bar_w
                if wm.set_volume then
                    wm.set_volume(math.max(0.0, math.min(1.0, pct)))
                end
                return true
            end
        end

    elseif state.active_tab == "timer" then
        local mode_y = state.y + 52
        if my >= mode_y and my <= mode_y + 26 then
            if mx >= state.x + 20 and mx <= state.x + 95 then
                state.clock_mode = "timer"
                return true
            elseif mx >= state.x + 102 and mx <= state.x + 185 then
                state.clock_mode = "stopwatch"
                return true
            end
        end

        local now = get_now()

        if state.clock_mode == "timer" then
            local pre_y = state.y + 86
            if my >= pre_y and my <= pre_y + 24 then
                local presets = {{
                    name = "5m",
                    s = 300
                }, {
                    name = "15m",
                    s = 900
                }, {
                    name = "25m",
                    s = 1500
                }, {
                    name = "45m",
                    s = 2700
                }}
                local pw = (state.w - 40) / #presets
                for i, p in ipairs(presets) do
                    local px = state.x + 20 + (i - 1) * pw
                    if mx >= px and mx <= px + pw - 6 then
                        state.timer_running = false
                        state.timer_total = p.s
                        state.timer_remain = p.s
                        return true
                    end
                end
            end

            local adj_y = state.y + 116
            if my >= adj_y and my <= adj_y + 24 then
                local buttons = {{
                    t = "-5m",
                    d = -300
                }, {
                    t = "-1m",
                    d = -60
                }, {
                    t = "+1m",
                    d = 60
                }, {
                    t = "+5m",
                    d = 300
                }}
                local bw = (state.w - 40) / #buttons
                for i, b in ipairs(buttons) do
                    local bx = state.x + 20 + (i - 1) * bw
                    if mx >= bx and mx <= bx + bw - 6 then
                        if state.timer_running then
                            state.timer_end_ts = math.max(now, state.timer_end_ts + b.d)
                        else
                            state.timer_remain = math.max(0.0, state.timer_remain + b.d)
                            state.timer_total = math.max(state.timer_remain, state.timer_total)
                        end
                        return true
                    end
                end
            end
        end

        local act_y = state.y + 154
        if my >= act_y and my <= act_y + 30 then
            local start_x = state.x + 20
            local btn_w = (state.w - 48) / 2
            if mx >= start_x and mx <= start_x + btn_w then
                if state.clock_mode == "stopwatch" then
                    if state.stopwatch_running then
                        state.stopwatch_base = state.stopwatch_base + (now - state.stopwatch_start_ts)
                        state.stopwatch_running = false
                    else
                        state.stopwatch_start_ts = now
                        state.stopwatch_running = true
                    end
                else
                    if state.timer_running then
                        state.timer_remain = math.max(0.0, state.timer_end_ts - now)
                        state.timer_running = false
                    else
                        if state.timer_remain <= 0.0 then
                            state.timer_remain = state.timer_total
                        end
                        state.timer_end_ts = now + state.timer_remain
                        state.timer_running = true
                    end
                end
                return true
            elseif mx >= start_x + btn_w + 8 and mx <= start_x + btn_w * 2 + 8 then
                if state.clock_mode == "stopwatch" then
                    state.stopwatch_running = false
                    state.stopwatch_base = 0.0
                else
                    state.timer_running = false
                    state.timer_remain = state.timer_total
                end
                return true
            end
        end

    elseif state.active_tab == "notes" then
        local btn_y = state.y + 162
        if my >= btn_y and my <= btn_y + 26 then
            if mx >= state.x + state.w - 136 and mx <= state.x + state.w - 82 then
                state.note_text = ""
                state.note_all_selected = false
                save_note()
                return true
            elseif mx >= state.x + state.w - 76 and mx <= state.x + state.w - 20 then
                state.note_active = false
                state.note_all_selected = false
                if wm.set_input_capture then
                    wm.set_input_capture(false)
                end
                save_note()
                return true
            end
        end

        local ny = state.y + 52
        if my >= ny and my <= ny + 100 then
            state.note_active = true
            state.note_all_selected = false
            if wm.set_input_capture then
                wm.set_input_capture(true)
            end
            return true
        end
    end

    return true
end

function isle.on_keyboard_input(vk, char, ctrl_down, shift_down)
    if not state.note_active then
        return false
    end

    if ctrl_down then
        if vk == 0x41 then -- Ctrl + A
            state.note_all_selected = true
            return true
        elseif vk == 0x43 then -- Ctrl + C
            if wm.set_clipboard_text then
                wm.set_clipboard_text(state.note_text)
            end
            return true
        elseif vk == 0x58 then -- Ctrl + X
            if wm.set_clipboard_text then
                wm.set_clipboard_text(state.note_text)
            end
            state.note_text = ""
            state.note_all_selected = false
            save_note()
            return true
        elseif vk == 0x56 then -- Ctrl + V
            if wm.get_clipboard_text then
                local clip = wm.get_clipboard_text()
                if clip and clip ~= "" then
                    clip = clip:gsub("[\r\n]", " ")
                    if state.note_all_selected then
                        state.note_text = clip
                        state.note_all_selected = false
                    else
                        state.note_text = state.note_text .. clip
                    end
                    save_note()
                end
            end
            return true
        elseif vk == 0x08 then -- Ctrl + Backspace
            if state.note_all_selected then
                state.note_text = ""
                state.note_all_selected = false
            else
                state.note_text = state.note_text:gsub("%s*[%w_]+%s*$", "")
            end
            save_note()
            return true
        end
    end

    if vk == 0x1B or vk == 0x0D then -- Esc or Enter
        state.note_active = false
        state.note_all_selected = false
        if wm.set_input_capture then
            wm.set_input_capture(false)
        end
        save_note()
        return true
    end

    if vk == 0x08 then -- Backspace
        if state.note_all_selected then
            state.note_text = ""
            state.note_all_selected = false
        elseif #state.note_text > 0 then
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
        if b >= 32 and #state.note_text < 350 then
            if state.note_all_selected then
                state.note_text = char
                state.note_all_selected = false
            else
                state.note_text = state.note_text .. char
            end
            return true
        end
    end

    return false
end

function isle.draw(opt_now)
    local now = opt_now or state.now or get_now()
    local sw, sh = wm.get_screen_size()
    local wx, wy, ww, wh = wm.get_work_area()
    local t = Quire.theme
    local accent = Quire.config.border_active or t.active_border_color

    ww = (ww and ww > 0) and ww or (sw or 1920)
    wx = wx or 0
    wy = wy or 0

    state.x = wx + math.floor((ww - state.w) * 0.5)
    state.y = wy + 6

    local ix = state.x
    local iy = state.y
    local iw = state.w
    local ih = state.h
    local rad = math.min(18.0, ih * 0.5)

    if ui.draw_shadow_rounded_rect then
        ui.draw_shadow_rounded_rect(ix, iy, iw, ih, rad, 0.0, 0.0, 0.0, 0.70, 14.0, 2.0)
    end

    ui.fill_rounded_rect(ix, iy, iw, ih, rad, 0.04, 0.05, 0.07, 0.96)
    ui.draw_rounded_rect(ix, iy, iw, ih, rad, 0.20, 0.22, 0.28, 0.50, 1.0)

    if ih < 50 then
        if state.popup_timer > 0 and state.popup_type == "volume" then
            local vol = math.max(0.0, math.min(1.0, state.last_volume or 0.0))
            ui.draw_text("VOL", ix + 16, iy + 11, 10, accent[1], accent[2], accent[3], 1.0, t.font_family)
            local bar_x = ix + 52
            local bar_y = iy + 14
            local bar_w = iw - 110
            ui.fill_rounded_rect(bar_x, bar_y, bar_w, 8, 4, 0.14, 0.16, 0.20, 0.9)
            ui.fill_rounded_rect(bar_x, bar_y, math.floor(bar_w * vol), 8, 4, accent[1], accent[2], accent[3], 1.0)
            ui.draw_text(math.floor(vol * 100) .. "%", bar_x + bar_w + 12, iy + 11, 10, 0.88, 0.90, 0.95, 1.0,
                t.font_family)
            return
        end

        local badge = "WS " .. tostring(Quire.current_workspace)
        ui.fill_rounded_rect(ix + 6, iy + 6, 44, 20, 6, 0.12, 0.14, 0.18, 0.9)
        ui.draw_text(badge, ix + 12, iy + 10, 9, accent[1], accent[2], accent[3], 1.0, t.font_family)

        local mid_text = ""
        local is_media = (state.last_track ~= "")
        if state.stopwatch_running then
            mid_text = "⏱ " .. format_time(get_current_stopwatch())
        elseif state.timer_running then
            mid_text = "⏳ " .. format_time(get_current_timer())
        elseif is_media then
            mid_text = state.last_track
        else
            mid_text = Quire.focused_window and wm.get_window_title(Quire.focused_window) or "QuireTWM"
        end

        if is_media and not state.stopwatch_running and not state.timer_running then
            local wx_bar = ix + 56
            for b = 1, 3 do
                local h_val = 4 + math.abs(math.sin(state.wave_anim + b * 1.4)) * 9
                ui.fill_rounded_rect(wx_bar + (b - 1) * 4, iy + 16 - math.floor(h_val * 0.5), 2, math.floor(h_val), 1,
                    accent[1], accent[2], accent[3], 1.0)
            end
        end

        local text_x = (is_media and not state.stopwatch_running and not state.timer_running) and (ix + 74) or (ix + 56)
        local max_w = iw - 170
        if ui.measure_text(mid_text, 10, t.font_family) > max_w then
            mid_text = mid_text:sub(1, 28) .. "..."
        end
        ui.draw_text(mid_text, text_x, iy + 10, 10, 0.90, 0.92, 0.96, 0.95, t.font_family)

        local stat_str = string.format("%d%% | %d%%", state.cached_cpu, state.cached_ram)
        local bat = state.cached_battery
        if bat.has_battery and bat.percentage >= 0 then
            stat_str = string.format("%d%%%s %s", bat.percentage, bat.is_charging and "⚡" or "", stat_str)
        end
        local sw_w = ui.measure_text(stat_str, 9, t.font_family)
        ui.draw_text(stat_str, ix + iw - sw_w - 14, iy + 10, 9, 0.55, 0.58, 0.65, 0.85, t.font_family)

        if state.popup_timer > 0 and state.popup_type == "timer_done" then
            ui.fill_rounded_rect(ix + 6, iy + 6, 26, 20, 6, 0.45, 0.15, 0.20, 0.95)
            ui.draw_text("!", ix + 17, iy + 9, 11, 1.0, 0.35, 0.35, 1.0, t.font_family)
            ui.draw_text("Timer completed!", ix + 42, iy + 10, 10, 1.0, 0.95, 0.95, 1.0, t.font_family)
            return
        end
        return
    end

    local tab_y = iy + 12
    local tabs = {"media", "timer", "notes", "system"}
    local tab_w = (iw - 28) / #tabs
    for i, tname in ipairs(tabs) do
        local tx = ix + 14 + (i - 1) * tab_w
        local is_sel = (state.active_tab == tname)
        if is_sel then
            ui.fill_rounded_rect(tx + 2, tab_y, tab_w - 4, 24, 6, accent[1], accent[2], accent[3], 0.22)
            ui.draw_rounded_rect(tx + 2, tab_y, tab_w - 4, 24, 6, accent[1], accent[2], accent[3], 0.60, 1.0)
        end
        local title_cap = tname:sub(1, 1):upper() .. tname:sub(2)
        local tw = ui.measure_text(title_cap, 10, t.font_family)
        ui.draw_text(title_cap, tx + math.floor((tab_w - tw) * 0.5), tab_y + 6, 10, is_sel and 1.0 or 0.60,
            is_sel and 1.0 or 0.62, is_sel and 1.0 or 0.70, 1.0, t.font_family)
    end

    ui.draw_line(ix + 14, iy + 44, ix + iw - 14, iy + 44, 0.16, 0.18, 0.24, 0.5, 1.0)

    if state.active_tab == "media" then
        local track_title = (state.last_track ~= "") and state.last_track or "No active media session"
        if ui.measure_text(track_title, 11, t.font_family) > (iw - 150) then
            track_title = track_title:sub(1, 38) .. "..."
        end
        ui.draw_text(track_title, ix + 20, iy + 66, 11, 0.94, 0.96, 1.0, 1.0, t.font_family)

        local btn_y = iy + 60
        local bx = ix + iw - 120
        ui.fill_rounded_rect(bx, btn_y, 30, 24, 4, 0.14, 0.16, 0.22, 0.9)
        ui.draw_text("<<", bx + 8, btn_y + 6, 9, 0.85, 0.88, 0.95, 1.0, t.font_family)

        ui.fill_rounded_rect(bx + 36, btn_y, 30, 24, 4, accent[1], accent[2], accent[3], 0.25)
        ui.draw_text("||", bx + 46, btn_y + 6, 9, accent[1], accent[2], accent[3], 1.0, t.font_family)

        ui.fill_rounded_rect(bx + 72, btn_y, 30, 24, 4, 0.14, 0.16, 0.22, 0.9)
        ui.draw_text(">>", bx + 79, btn_y + 6, 9, 0.85, 0.88, 0.95, 1.0, t.font_family)

        local vy = iy + 120
        ui.fill_rounded_rect(ix + 20, vy, 28, 22, 4, 0.12, 0.14, 0.18, 0.9)
        ui.draw_text("-", ix + 31, vy + 4, 11, 0.85, 0.88, 0.95, 1.0, t.font_family)

        local vol = math.max(0.0, math.min(1.0, state.last_volume or 0.0))
        local bar_x = ix + 56
        local bar_w = iw - 112
        ui.fill_rounded_rect(bar_x, vy + 7, bar_w, 8, 4, 0.12, 0.14, 0.18, 0.9)
        ui.fill_rounded_rect(bar_x, vy + 7, math.floor(bar_w * vol), 8, 4, accent[1], accent[2], accent[3], 1.0)

        ui.fill_rounded_rect(ix + iw - 48, vy, 28, 22, 4, 0.12, 0.14, 0.18, 0.9)
        ui.draw_text("+", ix + iw - 38, vy + 4, 11, 0.85, 0.88, 0.95, 1.0, t.font_family)

        local vol_str = "Volume: " .. math.floor(vol * 100) .. "%"
        ui.draw_text(vol_str, ix + 20, iy + 160, 10, 0.55, 0.58, 0.65, 0.9, t.font_family)

    elseif state.active_tab == "timer" then
        local mode_y = iy + 52
        local is_sw = (state.clock_mode == "stopwatch")

        ui.fill_rounded_rect(ix + 20, mode_y, 75, 24, 4, not is_sw and 0.25 or 0.10, not is_sw and 0.35 or 0.12,
            not is_sw and 0.50 or 0.16, 0.9)
        ui.draw_text("Timer", ix + 38, mode_y + 6, 9, not is_sw and 1.0 or 0.6, 1.0, 1.0, 1.0, t.font_family)

        ui.fill_rounded_rect(ix + 102, mode_y, 85, 24, 4, is_sw and 0.25 or 0.10, is_sw and 0.35 or 0.12,
            is_sw and 0.50 or 0.16, 0.9)
        ui.draw_text("Stopwatch", ix + 114, mode_y + 6, 9, is_sw and 1.0 or 0.6, 1.0, 1.0, 1.0, t.font_family)

        local cur_time = is_sw and get_current_stopwatch() or get_current_timer()
        local time_str = format_time(cur_time)
        ui.draw_text(time_str, ix + iw - 110, mode_y + 2, 17, 0.96, 0.98, 1.0, 1.0, t.font_family)

        if not is_sw then
            local pre_y = iy + 86
            local presets = {{
                name = "5m",
                s = 300
            }, {
                name = "15m",
                s = 900
            }, {
                name = "25m (Pomo)",
                s = 1500
            }, {
                name = "45m",
                s = 2700
            }}
            local pw = (iw - 40) / #presets
            for i, p in ipairs(presets) do
                local px = ix + 20 + (i - 1) * pw
                ui.fill_rounded_rect(px, pre_y, pw - 6, 22, 4, 0.12, 0.14, 0.18, 0.9)
                local tw = ui.measure_text(p.name, 9, t.font_family)
                ui.draw_text(p.name, px + math.floor((pw - 6 - tw) * 0.5), pre_y + 5, 9, 0.80, 0.84, 0.92, 1.0,
                    t.font_family)
            end

            local adj_y = iy + 116
            local buttons = {"-5m", "-1m", "+1m", "+5m"}
            local bw = (iw - 40) / #buttons
            for i, bname in ipairs(buttons) do
                local bx = ix + 20 + (i - 1) * bw
                ui.fill_rounded_rect(bx, adj_y, bw - 6, 22, 4, 0.10, 0.12, 0.16, 0.9)
                local tw = ui.measure_text(bname, 9, t.font_family)
                ui.draw_text(bname, bx + math.floor((bw - 6 - tw) * 0.5), adj_y + 5, 9, 0.70, 0.75, 0.85, 1.0,
                    t.font_family)
            end
        else
            ui.draw_text("Running stopwatch mode", ix + 20, iy + 100, 10, 0.55, 0.58, 0.65, 0.9, t.font_family)
        end

        local act_y = iy + 154
        local is_running = is_sw and state.stopwatch_running or state.timer_running
        local btn_w = (iw - 48) / 2
        ui.fill_rounded_rect(ix + 20, act_y, btn_w, 28, 4, is_running and 0.45 or 0.15, is_running and 0.15 or 0.35,
            0.22, 0.9)
        local start_txt = is_running and "Pause" or "Start"
        local st_w = ui.measure_text(start_txt, 10, t.font_family)
        ui.draw_text(start_txt, ix + 20 + math.floor((btn_w - st_w) * 0.5), act_y + 8, 10, 0.95, 0.98, 1.0, 1.0,
            t.font_family)

        ui.fill_rounded_rect(ix + 28 + btn_w, act_y, btn_w, 28, 4, 0.12, 0.14, 0.18, 0.9)
        local res_w = ui.measure_text("Reset", 10, t.font_family)
        ui.draw_text("Reset", ix + 28 + btn_w + math.floor((btn_w - res_w) * 0.5), act_y + 8, 10, 0.75, 0.78, 0.85, 1.0,
            t.font_family)

    elseif state.active_tab == "notes" then
        local ny = iy + 52
        local note_h = 100
        local is_editing = state.note_active
        ui.fill_rounded_rect(ix + 18, ny, iw - 36, note_h, 6, 0.07, 0.08, 0.11, 0.9)
        ui.draw_rounded_rect(ix + 18, ny, iw - 36, note_h, 6, accent[1], accent[2], accent[3],
            is_editing and 0.85 or 0.25, 1.0)

        if state.note_all_selected then
            ui.fill_rounded_rect(ix + 22, ny + 8, iw - 44, note_h - 16, 4, accent[1], accent[2], accent[3], 0.35)
        end

        local disp_note = state.note_text
        if is_editing and (math.floor(now * 2.5) % 2) == 0 and not state.note_all_selected then
            disp_note = disp_note .. "|"
        end
        ui.draw_text(disp_note, ix + 26, ny + 12, 10, is_editing and 0.98 or 0.70, 0.95, 0.98, 0.95, t.font_family)

        local by = iy + 162
        ui.draw_text(is_editing and "Ctrl+A/C/V supported. Enter to save" or "Click box to edit notes", ix + 20, by + 6,
            9, 0.45, 0.48, 0.55, 0.9, t.font_family)

        ui.fill_rounded_rect(ix + iw - 136, by, 54, 24, 4, 0.14, 0.16, 0.20, 0.9)
        ui.draw_text("Clear", ix + iw - 124, by + 6, 9, 0.75, 0.78, 0.85, 1.0, t.font_family)

        ui.fill_rounded_rect(ix + iw - 76, by, 56, 24, 4, accent[1], accent[2], accent[3], 0.25)
        ui.draw_text("Done", ix + iw - 62, by + 6, 9, accent[1], accent[2], accent[3], 1.0, t.font_family)

    elseif state.active_tab == "system" then
        local sy = iy + 56
        ui.draw_text("CPU Load:", ix + 20, sy, 10, 0.75, 0.78, 0.85, 1.0, t.font_family)
        local bar_w = iw - 160
        ui.fill_rounded_rect(ix + 90, sy + 3, bar_w, 8, 4, 0.12, 0.14, 0.18, 0.9)
        ui.fill_rounded_rect(ix + 90, sy + 3, math.floor(bar_w * (state.cached_cpu / 100.0)), 8, 4, accent[1],
            accent[2], accent[3], 1.0)
        ui.draw_text(state.cached_cpu .. "%", ix + 100 + bar_w, sy, 10, 0.90, 0.92, 0.96, 1.0, t.font_family)

        local my_bar = sy + 30
        ui.draw_text("RAM Load:", ix + 20, my_bar, 10, 0.75, 0.78, 0.85, 1.0, t.font_family)
        ui.fill_rounded_rect(ix + 90, my_bar + 3, bar_w, 8, 4, 0.12, 0.14, 0.18, 0.9)
        ui.fill_rounded_rect(ix + 90, my_bar + 3, math.floor(bar_w * (state.cached_ram / 100.0)), 8, 4, 0.4, 0.7, 0.5,
            1.0)
        ui.draw_text(state.cached_ram .. "%", ix + 100 + bar_w, my_bar, 10, 0.90, 0.92, 0.96, 1.0, t.font_family)

        local by_bar = my_bar + 30
        local bat = state.cached_battery
        if bat.has_battery and bat.percentage >= 0 then
            local bat_str = bat.percentage .. "%" .. (bat.is_charging and " [Charging]" or "")
            ui.draw_text("Battery:", ix + 20, by_bar, 10, 0.75, 0.78, 0.85, 1.0, t.font_family)
            ui.draw_text(bat_str, ix + 90, by_bar, 10, 0.85, 0.88, 0.95, 1.0, t.font_family)
            by_bar = by_bar + 30
        end

        local win_info = state.cached_win_info
        if ui.measure_text(win_info, 9, t.font_family) > (iw - 40) then
            win_info = win_info:sub(1, 46) .. "..."
        end
        ui.draw_text(win_info, ix + 20, by_bar + 4, 9, 0.50, 0.54, 0.62, 0.9, t.font_family)

        ui.draw_text(win_info, ix + 20, by_bar + 4, 9, 0.50, 0.54, 0.62, 0.9, t.font_family)
    end
end

return isle
