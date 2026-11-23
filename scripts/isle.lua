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
    mx = -1.0,
    my = -1.0,
    is_hovered = false,
    is_pinned = false,
    now = 0.0,

    tab_pill_x = 0.0,
    tab_pill_vx = 0.0,
    tab_pill_init = false,

    last_volume = 0.5,
    is_muted = false,
    popup_timer = 0.0,
    popup_type = nil,
    toast_msg = "",
    toast_level = "info",

    last_track = "",
    media_playing = false,
    media_pos = 0.0,
    media_dur = 0.0,

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
    note_cursor = 0,

    cached_cpu = 0,
    cached_ram = 0,
    cached_win_info = "Desktop",
    cached_battery = {
        percentage = -1,
        is_charging = false,
        has_battery = false
    },
    last_stat_time = -10.0,
    last_cpu_sample = -10.0,
    cpu_history = {},

    wave_anim = 0.0
}

local function utf8_char_count(s)
    if not s or s == "" then
        return 0
    end
    return utf8.len(s) or #s
end

local function utf8_sub(s, max_chars)
    if not s then
        return ""
    end
    local len = utf8.len(s)
    if not len or len <= max_chars then
        return s
    end
    local offset = utf8.offset(s, max_chars + 1)
    if offset then
        return s:sub(1, offset - 1) .. "..."
    end
    return s
end

local function utf8_slice_before(s, char_pos)
    if not s or s == "" or char_pos <= 0 then
        return ""
    end
    local len = utf8_char_count(s)
    if char_pos >= len then
        return s
    end
    local offset = utf8.offset(s, char_pos + 1)
    if offset then
        return s:sub(1, offset - 1)
    end
    return s
end

local function utf8_insert(s, char_pos, ins)
    local len = utf8_char_count(s)
    local pos = math.max(0, math.min(len, char_pos))
    if pos == 0 then
        return ins .. s
    elseif pos == len then
        return s .. ins
    end
    local offset = utf8.offset(s, pos + 1)
    if offset then
        return s:sub(1, offset - 1) .. ins .. s:sub(offset)
    end
    return s .. ins
end

local function utf8_remove_at(s, char_idx_1based)
    local len = utf8_char_count(s)
    if char_idx_1based < 1 or char_idx_1based > len then
        return s
    end
    local start_off = utf8.offset(s, char_idx_1based)
    local next_off = utf8.offset(s, char_idx_1based + 1)
    if start_off then
        if next_off then
            return s:sub(1, start_off - 1) .. s:sub(next_off)
        else
            return s:sub(1, start_off - 1)
        end
    end
    return s
end

local function is_rect_hovered(rx, ry, rw, rh)
    return state.mx >= rx and state.mx <= (rx + rw) and state.my >= ry and state.my <= (ry + rh)
end

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

function isle.show_toast(msg, level)
    state.toast_msg = tostring(msg or "")
    state.toast_level = level or "info"
    state.popup_timer = (state.toast_level == "error") and 4.5 or 2.5
    state.popup_type = "toast"
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
    state.note_cursor = utf8_char_count(state.note_text)

    if wm.get_volume then
        local v = wm.get_volume()
        state.last_volume = (v and v >= 0.0) and v or 0.5
    end
    if wm.is_muted then
        state.is_muted = wm.is_muted()
    end
    if wm.get_cpu_usage then
        state.cached_cpu = math.floor(wm.get_cpu_usage())
    end
    table.insert(state.cpu_history, state.cached_cpu)
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
    if state.media_playing then
        state.wave_anim = state.wave_anim + dt * 5.0
    end

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

    if now - state.last_cpu_sample >= 1.0 then
        state.last_cpu_sample = now
        table.insert(state.cpu_history, state.cached_cpu)
        if #state.cpu_history > 30 then
            table.remove(state.cpu_history, 1)
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

    if wm.is_muted then
        state.is_muted = wm.is_muted()
    end

    if wm.get_media_info then
        local info = wm.get_media_info()
        if info then
            local t = info.title or ""
            state.media_playing = info.playing == true
            state.media_pos = info.pos or 0.0
            state.media_dur = info.dur or 0.0
            if t ~= "" and t ~= state.last_track then
                state.last_track = t
                if state.popup_type ~= "toast" or state.popup_timer <= 0 then
                    state.popup_timer = 2.4
                    state.popup_type = "media"
                end
            elseif t == "" then
                state.last_track = ""
            end
        end
    elseif wm.get_media_title then
        local t = wm.get_media_title()
        if t ~= "" and t ~= state.last_track then
            state.last_track = t
            state.media_playing = true
            if state.popup_type ~= "toast" or state.popup_timer <= 0 then
                state.popup_timer = 2.4
                state.popup_type = "media"
            end
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
        elseif state.popup_type == "toast" then
            state.target_w = math.max(300.0, math.min(540.0, #state.toast_msg * 7.0 + 90.0))
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

    local tabs = {"media", "timer", "notes", "system"}
    local active_idx = 1
    for i, tname in ipairs(tabs) do
        if state.active_tab == tname then
            active_idx = i
            break
        end
    end
    local tab_w = (state.w - 28) / #tabs
    local target_pill_x = state.x + 14 + (active_idx - 1) * tab_w + 2
    if not state.tab_pill_init or state.h < 70 then
        state.tab_pill_x = target_pill_x
        state.tab_pill_vx = 0.0
        state.tab_pill_init = true
    else
        state.tab_pill_x, state.tab_pill_vx = solve_spring(state.tab_pill_x, state.tab_pill_vx, target_pill_x, 340, 26,
            1.0, dt)
    end
end

function isle.update_mouse(mx, my)
    state.mx = mx
    state.my = my
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
        local py = state.y + 52
        if my >= py and my <= py + 32 then
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

        local prog_y = state.y + 92
        if my >= prog_y and my <= prog_y + 20 then
            local px = state.x + 64
            local pw = state.w - 128
            if mx >= px and mx <= px + pw and state.media_dur > 0.0 then
                local pct = math.max(0.0, math.min(1.0, (mx - px) / pw))
                if wm.media_seek then
                    wm.media_seek(pct * state.media_dur)
                end
                return true
            end
        end

        local vy = state.y + 130
        if my >= vy and my <= vy + 26 then
            if mx >= state.x + 20 and mx <= state.x + 56 then
                if wm.set_muted then
                    state.is_muted = not state.is_muted
                    wm.set_muted(state.is_muted)
                end
                return true
            elseif mx >= state.x + 62 and mx <= state.x + 86 then
                if wm.set_volume then
                    wm.set_volume(math.max(0.0, state.last_volume - 0.05))
                end
                return true
            elseif mx >= state.x + state.w - 44 and mx <= state.x + state.w - 20 then
                if wm.set_volume then
                    wm.set_volume(math.min(1.0, state.last_volume + 0.05))
                end
                return true
            end
            local bar_x = state.x + 92
            local bar_w = state.w - 142
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
                state.note_cursor = 0
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
            state.note_cursor = utf8_char_count(state.note_text)
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

    local len = utf8_char_count(state.note_text)

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
            state.note_cursor = 0
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
                        state.note_cursor = utf8_char_count(clip)
                        state.note_all_selected = false
                    else
                        state.note_text = utf8_insert(state.note_text, state.note_cursor, clip)
                        state.note_cursor = state.note_cursor + utf8_char_count(clip)
                    end
                    save_note()
                end
            end
            return true
        elseif vk == 0x08 then -- Ctrl + Backspace
            if state.note_all_selected then
                state.note_text = ""
                state.note_cursor = 0
                state.note_all_selected = false
            else
                state.note_text = state.note_text:gsub("%s*[%w_]+%s*$", "")
                state.note_cursor = utf8_char_count(state.note_text)
            end
            save_note()
            return true
        end
    end

    if vk == 0x25 then -- Left
        state.note_all_selected = false
        state.note_cursor = math.max(0, state.note_cursor - 1)
        return true
    elseif vk == 0x27 then -- Right
        state.note_all_selected = false
        state.note_cursor = math.min(len, state.note_cursor + 1)
        return true
    elseif vk == 0x24 then -- Home
        state.note_all_selected = false
        state.note_cursor = 0
        return true
    elseif vk == 0x23 then -- End
        state.note_all_selected = false
        state.note_cursor = len
        return true
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
            state.note_cursor = 0
            state.note_all_selected = false
        elseif state.note_cursor > 0 then
            state.note_text = utf8_remove_at(state.note_text, state.note_cursor)
            state.note_cursor = math.max(0, state.note_cursor - 1)
        end
        return true
    end

    if vk == 0x2E then -- Delete
        if state.note_all_selected then
            state.note_text = ""
            state.note_cursor = 0
            state.note_all_selected = false
        elseif state.note_cursor < len then
            state.note_text = utf8_remove_at(state.note_text, state.note_cursor + 1)
        end
        return true
    end

    if char and #char > 0 then
        local b = char:byte(1)
        if b >= 32 and #state.note_text < 350 then
            if state.note_all_selected then
                state.note_text = char
                state.note_cursor = 1
                state.note_all_selected = false
            else
                state.note_text = utf8_insert(state.note_text, state.note_cursor, char)
                state.note_cursor = state.note_cursor + 1
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
        if state.popup_timer > 0 and state.popup_type == "toast" then
            local badge_col = accent
            local badge_txt = "INFO"
            if state.toast_level == "error" then
                badge_col = {0.95, 0.28, 0.32}
                badge_txt = "ERR"
            elseif state.toast_level == "success" then
                badge_col = {0.25, 0.85, 0.50}
                badge_txt = "OK"
            end
            ui.fill_rounded_rect(ix + 6, iy + 6, 40, 24, 6, badge_col[1], badge_col[2], badge_col[3], 0.22)
            ui.draw_rounded_rect(ix + 6, iy + 6, 40, 24, 6, badge_col[1], badge_col[2], badge_col[3], 0.65, 1.0)
            local btw = ui.measure_text(badge_txt, 9, t.font_family)
            ui.draw_text(badge_txt, ix + 6 + math.floor((40 - btw) * 0.5), iy + 11, 9, badge_col[1], badge_col[2],
                badge_col[3], 1.0, t.font_family)

            local msg = state.toast_msg
            if ui.measure_text(msg, 10, t.font_family) > (iw - 66) then
                msg = utf8_sub(msg, 46)
            end
            ui.draw_text(msg, ix + 56, iy + 11, 10, 0.94, 0.96, 1.0, 1.0, t.font_family)
            return
        end

        if state.popup_timer > 0 and state.popup_type == "volume" then
            local vol = math.max(0.0, math.min(1.0, state.last_volume or 0.0))
            ui.draw_text(state.is_muted and "MUTE" or "VOL", ix + 14, iy + 11, 10, accent[1], accent[2], accent[3], 1.0,
                t.font_family)
            local bar_x = ix + 56
            local bar_y = iy + 14
            local bar_w = iw - 114
            ui.fill_rounded_rect(bar_x, bar_y, bar_w, 8, 4, 0.14, 0.16, 0.20, 0.9)
            local fill_col = state.is_muted and {0.5, 0.5, 0.55} or accent
            ui.fill_rounded_rect(bar_x, bar_y, math.floor(bar_w * vol), 8, 4, fill_col[1], fill_col[2], fill_col[3], 1.0)
            ui.draw_text(math.floor(vol * 100) .. "%", bar_x + bar_w + 12, iy + 11, 10, 0.88, 0.90, 0.95, 1.0,
                t.font_family)
            return
        end

        if state.popup_timer > 0 and state.popup_type == "timer_done" then
            ui.fill_rounded_rect(ix + 6, iy + 6, 26, 20, 6, 0.45, 0.15, 0.20, 0.95)
            ui.draw_text("!", ix + 17, iy + 9, 11, 1.0, 0.35, 0.35, 1.0, t.font_family)
            ui.draw_text("Timer completed!", ix + 42, iy + 10, 10, 1.0, 0.95, 0.95, 1.0, t.font_family)
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
                local h_val = state.media_playing and (4 + math.abs(math.sin(state.wave_anim + b * 1.4)) * 9) or 4
                ui.fill_rounded_rect(wx_bar + (b - 1) * 4, iy + 16 - math.floor(h_val * 0.5), 2, math.floor(h_val), 1,
                    accent[1], accent[2], accent[3], state.media_playing and 1.0 or 0.45)
            end
        end

        local text_x = (is_media and not state.stopwatch_running and not state.timer_running) and (ix + 74) or (ix + 56)
        local max_w = iw - 170
        if ui.measure_text(mid_text, 10, t.font_family) > max_w then
            mid_text = utf8_sub(mid_text, 26)
        end

        ui.draw_text(mid_text, text_x, iy + 10, 10, 0.90, 0.92, 0.96, 0.95, t.font_family)

        local stat_str = string.format("%d%% | %d%%", state.cached_cpu, state.cached_ram)
        local bat = state.cached_battery
        if bat.has_battery and bat.percentage >= 0 then
            stat_str = string.format("%d%%%s %s", bat.percentage, bat.is_charging and "⚡" or "", stat_str)
        end
        local sw_w = ui.measure_text(stat_str, 9, t.font_family)
        ui.draw_text(stat_str, ix + iw - sw_w - 14, iy + 10, 9, 0.55, 0.58, 0.65, 0.85, t.font_family)

        if state.timer_running and state.timer_total > 0 then
            local frac = math.max(0.0, math.min(1.0, get_current_timer() / state.timer_total))
            local line_w = math.floor((iw - 32) * frac)
            if line_w > 0 then
                ui.fill_rounded_rect(ix + 16, iy + ih - 3, line_w, 2, 1, accent[1], accent[2], accent[3], 0.9)
            end
        end
        return
    end

    local tab_y = iy + 12
    local tabs = {"media", "timer", "notes", "system"}
    local tab_w = (iw - 28) / #tabs

    ui.fill_rounded_rect(state.tab_pill_x, tab_y, tab_w - 4, 24, 6, accent[1], accent[2], accent[3], 0.22)
    ui.draw_rounded_rect(state.tab_pill_x, tab_y, tab_w - 4, 24, 6, accent[1], accent[2], accent[3], 0.60, 1.0)

    for i, tname in ipairs(tabs) do
        local tx = ix + 14 + (i - 1) * tab_w
        local is_sel = (state.active_tab == tname)
        local is_hov = is_rect_hovered(tx + 2, tab_y, tab_w - 4, 24)
        if not is_sel and is_hov then
            ui.fill_rounded_rect(tx + 2, tab_y, tab_w - 4, 24, 6, 0.25, 0.28, 0.35, 0.35)
        end
        local title_cap = tname:sub(1, 1):upper() .. tname:sub(2)
        local tw = ui.measure_text(title_cap, 10, t.font_family)
        local c_val = is_sel and 1.0 or (is_hov and 0.88 or 0.60)
        ui.draw_text(title_cap, tx + math.floor((tab_w - tw) * 0.5), tab_y + 6, 10, c_val,
            is_sel and 1.0 or (is_hov and 0.90 or 0.62), is_sel and 1.0 or (is_hov and 0.95 or 0.70), 1.0,
            t.font_family)
    end

    ui.draw_line(ix + 14, iy + 44, ix + iw - 14, iy + 44, 0.16, 0.18, 0.24, 0.5, 1.0)

    if state.active_tab == "media" then
        local track_title = (state.last_track ~= "") and state.last_track or "No active media session"
        if ui.measure_text(track_title, 11, t.font_family) > (iw - 150) then
            track_title = utf8_sub(track_title, 34)
        end

        ui.draw_text(track_title, ix + 20, iy + 58, 11, 0.94, 0.96, 1.0, 1.0, t.font_family)

        local btn_y = iy + 52
        local bx = ix + iw - 120
        local h_prev = is_rect_hovered(bx, btn_y, 30, 24)
        ui.fill_rounded_rect(bx, btn_y, 30, 24, 4, h_prev and 0.22 or 0.14, h_prev and 0.25 or 0.16,
            h_prev and 0.32 or 0.22, 0.9)
        ui.draw_text("<<", bx + 8, btn_y + 6, 9, 0.85, 0.88, 0.95, 1.0, t.font_family)

        local h_pp = is_rect_hovered(bx + 36, btn_y, 30, 24)
        ui.fill_rounded_rect(bx + 36, btn_y, 30, 24, 4, accent[1], accent[2], accent[3], h_pp and 0.40 or 0.25)
        local pp_icon = state.media_playing and "⏸" or "▶"
        local pp_w = ui.measure_text(pp_icon, 10, t.font_family)
        ui.draw_text(pp_icon, bx + 36 + math.floor((30 - pp_w) * 0.5), btn_y + 5, 10, accent[1], accent[2], accent[3],
            1.0, t.font_family)

        local h_next = is_rect_hovered(bx + 72, btn_y, 30, 24)
        ui.fill_rounded_rect(bx + 72, btn_y, 30, 24, 4, h_next and 0.22 or 0.14, h_next and 0.25 or 0.16,
            h_next and 0.32 or 0.22, 0.9)
        ui.draw_text(">>", bx + 79, btn_y + 6, 9, 0.85, 0.88, 0.95, 1.0, t.font_family)

        local prog_y = iy + 96
        local pos_str = format_time(state.media_pos)
        local dur_str = format_time(state.media_dur)
        ui.draw_text(pos_str, ix + 20, prog_y - 1, 9, 0.65, 0.68, 0.75, 0.95, t.font_family)

        local px = ix + 64
        local pw = iw - 128
        local prog_frac = (state.media_dur > 0.0) and math.max(0.0, math.min(1.0, state.media_pos / state.media_dur)) or
                              0.0
        local h_prog = is_rect_hovered(px, prog_y - 4, pw, 16)
        ui.fill_rounded_rect(px, prog_y + 2, pw, h_prog and 7 or 5, 3, 0.12, 0.14, 0.18, 0.9)
        if prog_frac > 0 then
            ui.fill_rounded_rect(px, prog_y + 2, math.floor(pw * prog_frac), h_prog and 7 or 5, 3, accent[1],
                accent[2], accent[3], 1.0)
        end
        ui.draw_text(dur_str, ix + iw - 54, prog_y - 1, 9, 0.65, 0.68, 0.75, 0.95, t.font_family)

        local vy = iy + 130
        local h_mute = is_rect_hovered(ix + 20, vy, 36, 22)
        if state.is_muted then
            ui.fill_rounded_rect(ix + 20, vy, 36, 22, 4, 0.55, 0.18, 0.22, h_mute and 0.95 or 0.80)
            ui.draw_text("MUTE", ix + 23, vy + 5, 8, 1.0, 0.85, 0.85, 1.0, t.font_family)
        else
            ui.fill_rounded_rect(ix + 20, vy, 36, 22, 4, h_mute and 0.22 or 0.12, h_mute and 0.25 or 0.14,
                h_mute and 0.30 or 0.18, 0.9)
            ui.draw_text("MUTE", ix + 23, vy + 5, 8, 0.70, 0.74, 0.82, 1.0, t.font_family)
        end

        local h_vminus = is_rect_hovered(ix + 62, vy, 24, 22)
        ui.fill_rounded_rect(ix + 62, vy, 24, 22, 4, h_vminus and 0.22 or 0.12, h_vminus and 0.25 or 0.14,
            h_vminus and 0.30 or 0.18, 0.9)
        ui.draw_text("-", ix + 71, vy + 4, 11, 0.85, 0.88, 0.95, 1.0, t.font_family)

        local vol = math.max(0.0, math.min(1.0, state.last_volume or 0.0))
        local bar_x = ix + 92
        local bar_w = iw - 142
        ui.fill_rounded_rect(bar_x, vy + 7, bar_w, 8, 4, 0.12, 0.14, 0.18, 0.9)
        local vcol = state.is_muted and {0.45, 0.48, 0.54} or accent
        ui.fill_rounded_rect(bar_x, vy + 7, math.floor(bar_w * vol), 8, 4, vcol[1], vcol[2], vcol[3], 1.0)

        local h_vplus = is_rect_hovered(ix + iw - 44, vy, 24, 22)
        ui.fill_rounded_rect(ix + iw - 44, vy, 24, 22, 4, h_vplus and 0.22 or 0.12, h_vplus and 0.25 or 0.14,
            h_vplus and 0.30 or 0.18, 0.9)
        ui.draw_text("+", ix + iw - 35, vy + 4, 11, 0.85, 0.88, 0.95, 1.0, t.font_family)

        local vol_str = state.is_muted and ("Muted (" .. math.floor(vol * 100) .. "%)") or
                            ("Volume: " .. math.floor(vol * 100) .. "%")
        ui.draw_text(vol_str, ix + 20, iy + 168, 10, 0.55, 0.58, 0.65, 0.9, t.font_family)

    elseif state.active_tab == "timer" then
        local mode_y = iy + 52
        local is_sw = (state.clock_mode == "stopwatch")

        local h_tm = is_rect_hovered(ix + 20, mode_y, 75, 24)
        ui.fill_rounded_rect(ix + 20, mode_y, 75, 24, 4, not is_sw and 0.25 or (h_tm and 0.18 or 0.10),
            not is_sw and 0.35 or (h_tm and 0.20 or 0.12), not is_sw and 0.50 or (h_tm and 0.26 or 0.16), 0.9)
        ui.draw_text("Timer", ix + 38, mode_y + 6, 9, not is_sw and 1.0 or 0.65, 1.0, 1.0, 1.0, t.font_family)

        local h_sw = is_rect_hovered(ix + 102, mode_y, 85, 24)
        ui.fill_rounded_rect(ix + 102, mode_y, 85, 24, 4, is_sw and 0.25 or (h_sw and 0.18 or 0.10),
            is_sw and 0.35 or (h_sw and 0.20 or 0.12), is_sw and 0.50 or (h_sw and 0.26 or 0.16), 0.9)
        ui.draw_text("Stopwatch", ix + 114, mode_y + 6, 9, is_sw and 1.0 or 0.65, 1.0, 1.0, 1.0, t.font_family)

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
                local h_p = is_rect_hovered(px, pre_y, pw - 6, 22)
                ui.fill_rounded_rect(px, pre_y, pw - 6, 22, 4, h_p and 0.20 or 0.12, h_p and 0.23 or 0.14,
                    h_p and 0.29 or 0.18, 0.9)
                local tw = ui.measure_text(p.name, 9, t.font_family)
                ui.draw_text(p.name, px + math.floor((pw - 6 - tw) * 0.5), pre_y + 5, 9, 0.80, 0.84, 0.92, 1.0,
                    t.font_family)
            end

            local adj_y = iy + 116
            local buttons = {"-5m", "-1m", "+1m", "+5m"}
            local bw = (iw - 40) / #buttons
            for i, bname in ipairs(buttons) do
                local bx = ix + 20 + (i - 1) * bw
                local h_b = is_rect_hovered(bx, adj_y, bw - 6, 22)
                ui.fill_rounded_rect(bx, adj_y, bw - 6, 22, 4, h_b and 0.18 or 0.10, h_b and 0.21 or 0.12,
                    h_b and 0.27 or 0.16, 0.9)
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
        local h_st = is_rect_hovered(ix + 20, act_y, btn_w, 28)
        ui.fill_rounded_rect(ix + 20, act_y, btn_w, 28, 4, is_running and (h_st and 0.55 or 0.45) or
            (h_st and 0.22 or 0.15), is_running and (h_st and 0.20 or 0.15) or (h_st and 0.45 or 0.35), 0.22, 0.9)
        local start_txt = is_running and "Pause" or "Start"
        local st_w = ui.measure_text(start_txt, 10, t.font_family)
        ui.draw_text(start_txt, ix + 20 + math.floor((btn_w - st_w) * 0.5), act_y + 8, 10, 0.95, 0.98, 1.0, 1.0,
            t.font_family)

        local h_rs = is_rect_hovered(ix + 28 + btn_w, act_y, btn_w, 28)
        ui.fill_rounded_rect(ix + 28 + btn_w, act_y, btn_w, 28, 4, h_rs and 0.20 or 0.12, h_rs and 0.22 or 0.14,
            h_rs and 0.28 or 0.18, 0.9)
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

        ui.draw_text(state.note_text, ix + 26, ny + 12, 10, is_editing and 0.98 or 0.70, 0.95, 0.98, 0.95, t.font_family)

        if is_editing and (math.floor(now * 2.5) % 2) == 0 and not state.note_all_selected then
            local before = utf8_slice_before(state.note_text, state.note_cursor)
            local cx = ix + 26 + ui.measure_text(before, 10, t.font_family)
            ui.fill_rounded_rect(cx, ny + 11, 2, 13, 1, accent[1], accent[2], accent[3], 1.0)
        end

        local by = iy + 162
        ui.draw_text(is_editing and "Arrows/Home/End, Ctrl+A/C/V. Enter to save" or "Click box to edit notes",
            ix + 20, by + 6, 9, 0.45, 0.48, 0.55, 0.9, t.font_family)

        local h_clr = is_rect_hovered(ix + iw - 136, by, 54, 24)
        ui.fill_rounded_rect(ix + iw - 136, by, 54, 24, 4, h_clr and 0.22 or 0.14, h_clr and 0.24 or 0.16,
            h_clr and 0.30 or 0.20, 0.9)
        ui.draw_text("Clear", ix + iw - 124, by + 6, 9, 0.75, 0.78, 0.85, 1.0, t.font_family)

        local h_done = is_rect_hovered(ix + iw - 76, by, 56, 24)
        ui.fill_rounded_rect(ix + iw - 76, by, 56, 24, 4, accent[1], accent[2], accent[3], h_done and 0.40 or 0.25)
        ui.draw_text("Done", ix + iw - 62, by + 6, 9, accent[1], accent[2], accent[3], 1.0, t.font_family)

    elseif state.active_tab == "system" then
        local sy = iy + 52
        ui.draw_text("CPU Load (30s): " .. state.cached_cpu .. "%", ix + 20, sy, 10, 0.75, 0.78, 0.85, 1.0, t.font_family)

        local gx = ix + 20
        local gy = sy + 18
        local gw = iw - 40
        local gh = 44
        ui.fill_rounded_rect(gx, gy, gw, gh, 5, 0.08, 0.09, 0.13, 0.95)
        ui.draw_rounded_rect(gx, gy, gw, gh, 5, 0.18, 0.20, 0.26, 0.6, 1.0)
        ui.draw_line(gx + 4, gy + math.floor(gh * 0.5), gx + gw - 4, gy + math.floor(gh * 0.5), 0.20, 0.22, 0.28, 0.35,
            1.0)

        local hist = state.cpu_history
        local n = #hist
        if n >= 2 then
            local step_x = (gw - 12) / 29.0
            local start_slot = 30 - n
            for i = 1, n - 1 do
                local x1 = gx + 6 + (start_slot + i - 1) * step_x
                local x2 = gx + 6 + (start_slot + i) * step_x
                local y1 = gy + gh - 4 - (math.max(0, math.min(100, hist[i])) / 100.0) * (gh - 8)
                local y2 = gy + gh - 4 - (math.max(0, math.min(100, hist[i + 1])) / 100.0) * (gh - 8)
                ui.draw_line(x1, y1, x2, y2, accent[1], accent[2], accent[3], 0.95, 1.8)
            end
        elseif n == 1 then
            local y1 = gy + gh - 4 - (math.max(0, math.min(100, hist[1])) / 100.0) * (gh - 8)
            ui.draw_line(gx + 6, y1, gx + gw - 6, y1, accent[1], accent[2], accent[3], 0.95, 1.8)
        end

        local my_bar = gy + gh + 12
        local bar_w = iw - 160
        ui.draw_text("RAM Load:", ix + 20, my_bar, 10, 0.75, 0.78, 0.85, 1.0, t.font_family)
        ui.fill_rounded_rect(ix + 90, my_bar + 3, bar_w, 8, 4, 0.12, 0.14, 0.18, 0.9)
        ui.fill_rounded_rect(ix + 90, my_bar + 3, math.floor(bar_w * (state.cached_ram / 100.0)), 8, 4, 0.4, 0.7, 0.5,
            1.0)
        ui.draw_text(state.cached_ram .. "%", ix + 100 + bar_w, my_bar, 10, 0.90, 0.92, 0.96, 1.0, t.font_family)

        local by_bar = my_bar + 24
        local bat = state.cached_battery
        if bat.has_battery and bat.percentage >= 0 then
            local bat_str = bat.percentage .. "%" .. (bat.is_charging and " [Charging]" or "")
            ui.draw_text("Battery:", ix + 20, by_bar, 10, 0.75, 0.78, 0.85, 1.0, t.font_family)
            ui.draw_text(bat_str, ix + 90, by_bar, 10, 0.85, 0.88, 0.95, 1.0, t.font_family)
            by_bar = by_bar + 22
        end

        local win_info = state.cached_win_info or "Desktop"
        if ui.measure_text(win_info, 9, t.font_family) > (iw - 40) then
            win_info = utf8_sub(win_info, 44)
        end

        ui.draw_text(win_info, ix + 20, by_bar + 4, 9, 0.50, 0.54, 0.62, 0.9, t.font_family)
    end
end

return isle
