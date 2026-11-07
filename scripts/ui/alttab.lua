local alttab = {}

Quire.alttab_active = false
Quire.alttab_index = 1
Quire.alttab_items = {}
Quire.focus_history = Quire.focus_history or {}

local anim_cx = 0.0
local live_thumbnails = {}

local function is_valid(hwnd)
    if not hwnd or hwnd == 0 or hwnd == g_overlay_hwnd then
        return false
    end
    if not wm.is_window(hwnd) then
        return false
    end
    if Quire.closing_windows and Quire.closing_windows[hwnd] then
        return false
    end
    return true
end

function alttab.record_focus(hwnd)
    if not hwnd or hwnd == 0 or hwnd == g_overlay_hwnd then
        return
    end
    for i = #Quire.focus_history, 1, -1 do
        if Quire.focus_history[i] == hwnd then
            table.remove(Quire.focus_history, i)
        end
    end
    table.insert(Quire.focus_history, 1, hwnd)
    while #Quire.focus_history > 32 do
        table.remove(Quire.focus_history)
    end
end

local function cleanup_all_thumbnails()
    if wm.destroy_thumbnail then
        for hwnd, thumb_id in pairs(live_thumbnails) do
            wm.destroy_thumbnail(thumb_id)
        end
    end
    live_thumbnails = {}
end

local function get_window_meta(hwnd)
    local col_idx, _, _, ws_id = Quire.find_window_pos(hwnd)
    local badge = ws_id and ("WS " .. tostring(ws_id)) or "FLOAT"
    if hwnd == Quire.scratchpad_hwnd then
        badge = "SP"
        ws_id = nil
    end
    local title = wm.get_window_title(hwnd)
    local proc = wm.get_process_name and wm.get_process_name(hwnd) or "App"
    if title == "" then
        title = proc
    end
    return {
        hwnd = hwnd,
        title = title,
        proc = proc,
        badge = badge,
        ws_id = ws_id
    }
end

local function rebuild_list()
    Quire.alttab_items = {}
    local seen = {}

    for _, hwnd in ipairs(Quire.focus_history) do
        if is_valid(hwnd) and not seen[hwnd] then
            seen[hwnd] = true
            table.insert(Quire.alttab_items, get_window_meta(hwnd))
        end
    end

    for ws_id, ws in pairs(Quire.workspaces) do
        if ws.columns then
            for _, col in ipairs(ws.columns) do
                for _, hwnd in ipairs(col.windows) do
                    if is_valid(hwnd) and not seen[hwnd] then
                        seen[hwnd] = true
                        table.insert(Quire.alttab_items, get_window_meta(hwnd))
                    end
                end
            end
        end
    end

    for hwnd, _ in pairs(Quire.floating_windows) do
        if is_valid(hwnd) and not seen[hwnd] then
            seen[hwnd] = true
            table.insert(Quire.alttab_items, get_window_meta(hwnd))
        end
    end

    if Quire.scratchpad_hwnd and is_valid(Quire.scratchpad_hwnd) and not seen[Quire.scratchpad_hwnd] then
        seen[Quire.scratchpad_hwnd] = true
        table.insert(Quire.alttab_items, get_window_meta(Quire.scratchpad_hwnd))
    end

    local all_wins = wm.enumerate_windows and wm.enumerate_windows() or {}
    for _, hwnd in ipairs(all_wins) do
        if not seen[hwnd] and is_valid(hwnd) then
            seen[hwnd] = true
            table.insert(Quire.alttab_items, get_window_meta(hwnd))
        end
    end
end

function alttab.action(action_type)
    if action_type == "next" or action_type == "prev" then
        if not Quire.alttab_active then
            Quire.alttab_active = true
            rebuild_list()
            Quire.alttab_index = (#Quire.alttab_items >= 2) and 2 or 1
            anim_cx = 0.0
        else
            local count = #Quire.alttab_items
            if count > 0 then
                if action_type == "next" then
                    Quire.alttab_index = (Quire.alttab_index % count) + 1
                else
                    Quire.alttab_index = (Quire.alttab_index - 2 + count) % count + 1
                end
            end
        end

    elseif action_type == "commit" then
        if Quire.alttab_active then
            local item = Quire.alttab_items[Quire.alttab_index]
            cleanup_all_thumbnails()
            Quire.alttab_active = false
            Quire.alttab_items = {}

            if item and is_valid(item.hwnd) then
                if item.hwnd == Quire.scratchpad_hwnd then
                    if not Quire.scratchpad_visible then
                        Quire.toggle_scratchpad()
                    else
                        wm.focus_window(item.hwnd)
                    end
                else
                    if item.ws_id and item.ws_id ~= Quire.current_workspace then
                        Quire.switch_workspace(item.ws_id)
                    end
                    wm.cloak_window(item.hwnd, false)
                    wm.focus_window(item.hwnd)
                    Quire.focused_window = item.hwnd
                    alttab.record_focus(item.hwnd)
                    Quire.retile()
                end
            end
        end

    elseif action_type == "cancel" then
        cleanup_all_thumbnails()
        Quire.alttab_active = false
        Quire.alttab_items = {}
    end
end

local function truncate_utf8(str, max_w, font, size)
    if ui.measure_text(str, size, font) <= max_w then
        return str
    end
    local len = utf8.len(str)
    if not len then
        return str
    end
    while len > 1 do
        len = len - 1
        local byte_offset = utf8.offset(str, len + 1)
        if byte_offset then
            local candidate = str:sub(1, byte_offset - 1) .. "..."
            if ui.measure_text(candidate, size, font) <= max_w then
                return candidate
            end
        end
    end
    return "..."
end

function alttab.draw()
    if not Quire.alttab_active then
        cleanup_all_thumbnails()
        return
    end

    local count = #Quire.alttab_items
    if count == 0 then
        cleanup_all_thumbnails()
        return
    end

    local sw, sh = wm.get_screen_size()
    local t = Quire.theme
    local accent = Quire.config.border_active or t.active_border_color

    ui.fill_rect(0, 0, sw, sh, 0.02, 0.02, 0.04, 0.65)

    local card_w = 230
    local card_h = 180
    local gap_x = 16

    local max_visible = math.min(count, math.max(3, math.floor((sw - 120) / (card_w + gap_x))))

    local total_w = (max_visible * card_w) + ((max_visible - 1) * gap_x)
    local start_x = math.floor((sw - total_w) / 2)
    local start_y = math.floor((sh - card_h) / 2)

    local offset = 0
    if count > max_visible then
        offset = math.max(0, math.min(count - max_visible, Quire.alttab_index - math.floor(max_visible / 2) - 1))
    end

    local selected_screen_x = start_x + (Quire.alttab_index - 1 - offset) * (card_w + gap_x)
    if anim_cx == 0.0 then
        anim_cx = selected_screen_x
    else
        anim_cx = anim_cx + (selected_screen_x - anim_cx) * 0.35
    end

    if ui.draw_glow_rounded_rect then
        ui.draw_glow_rounded_rect(anim_cx - 4, start_y - 4, card_w + 8, card_h + 8, t.rounding + 2,
            accent[1], accent[2], accent[3], 0.8, 8.0, 3.0)
    end
    ui.draw_rounded_rect(anim_cx - 2, start_y - 2, card_w + 4, card_h + 4, t.rounding + 2,
        accent[1], accent[2], accent[3], 1.0, 2.0)

    local visible_hwnds = {}

    for i = 1, max_visible do
        local item_idx = i + offset
        local item = Quire.alttab_items[item_idx]
        if item then
            local cx = start_x + (i - 1) * (card_w + gap_x)
            local cy = start_y
            local is_sel = (item_idx == Quire.alttab_index)

            ui.fill_rounded_rect(cx, cy, card_w, card_h, t.rounding, 0.07, 0.08, 0.11, is_sel and 0.95 or 0.80)
            ui.draw_rounded_rect(cx, cy, card_w, card_h, t.rounding, t.border_color[1], t.border_color[2],
                t.border_color[3], is_sel and 0.5 or 0.25, 1.0)

            local thumb_x = cx + 10
            local thumb_y = cy + 36
            local thumb_w = card_w - 20
            local thumb_h = card_h - 68

            ui.fill_rounded_rect(thumb_x, thumb_y, thumb_w, thumb_h, 6, 0.03, 0.03, 0.05, 0.90)

            visible_hwnds[item.hwnd] = true

            if wm.create_thumbnail and wm.update_thumbnail then
                local thumb_id = live_thumbnails[item.hwnd]
                if not thumb_id then
                    thumb_id = wm.create_thumbnail(item.hwnd)
                    if thumb_id and thumb_id ~= 0 then
                        live_thumbnails[item.hwnd] = thumb_id
                    end
                end

                if thumb_id and thumb_id ~= 0 then
                    local alpha = is_sel and 255 or 215
                    wm.update_thumbnail(thumb_id, thumb_x, thumb_y, thumb_w, thumb_h, alpha)
                end
            end

            ui.draw_text(item.proc, cx + 12, cy + 10, 11, accent[1], accent[2], accent[3], 1.0, t.font_family)

            local badge_w = ui.measure_text(item.badge, 9, t.font_family) + 10
            local badge_x = cx + card_w - badge_w - 10
            ui.fill_rounded_rect(badge_x, cy + 9, badge_w, 16, 4, 0.14, 0.16, 0.22, 0.90)
            ui.draw_text(item.badge, badge_x + 5, cy + 11, 9, 0.8, 0.85, 0.95, 0.9, t.font_family)

            local title_str = truncate_utf8(item.title, card_w - 24, t.font_family, 10)
            ui.draw_text(title_str, cx + 12, cy + card_h - 22, 10, 0.92, 0.92, 0.96, is_sel and 1.0 or 0.65,
                t.font_family)
        end
    end

    for hwnd, thumb_id in pairs(live_thumbnails) do
        if not visible_hwnds[hwnd] then
            if wm.destroy_thumbnail then
                wm.destroy_thumbnail(thumb_id)
            end
            live_thumbnails[hwnd] = nil
        end
    end
end

return alttab