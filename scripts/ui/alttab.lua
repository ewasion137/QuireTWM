local alttab = {}

Quire.alttab_active = false
Quire.alttab_index = 1
Quire.alttab_items = {}
Quire.focus_history = Quire.focus_history or {}

local anim_cx = 0.0
local active_thumb = nil
local active_thumb_hwnd = nil

local function is_valid(hwnd)
    return hwnd and wm.is_window(hwnd) and wm.is_window_visible(hwnd)
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

local function cleanup_thumbnail()
    if active_thumb and wm.destroy_thumbnail then
        wm.destroy_thumbnail(active_thumb)
        active_thumb = nil
        active_thumb_hwnd = nil
    end
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

    local all_wins = wm.enumerate_windows()
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
            cleanup_thumbnail()
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
        cleanup_thumbnail()
        Quire.alttab_active = false
        Quire.alttab_items = {}
    end
end

function alttab.draw()
    if not Quire.alttab_active then
        cleanup_thumbnail()
        return
    end

    local count = #Quire.alttab_items
    if count == 0 then
        cleanup_thumbnail()
        return
    end

    local sw, sh = wm.get_screen_size()
    local t = Quire.theme
    local accent = Quire.config.border_active or t.active_border_color

    ui.fill_rect(0, 0, sw, sh, 0.02, 0.02, 0.04, 0.65)

    local max_visible = math.min(count, 7)
    local card_w = 260
    local card_h = 200
    local gap_x = 18

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

    local active_target_hwnd = nil
    local active_rect = nil

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

            local thumb_x = cx + 12
            local thumb_y = cy + 40
            local thumb_w = card_w - 24
            local thumb_h = card_h - 78

            ui.fill_rounded_rect(thumb_x, thumb_y, thumb_w, thumb_h, 6, 0.03, 0.03, 0.05, 0.90)

            if is_sel then
                active_target_hwnd = item.hwnd
                active_rect = { thumb_x, thumb_y, thumb_w, thumb_h }
            end

            ui.draw_text(item.proc, cx + 14, cy + 12, 11, accent[1], accent[2], accent[3], 1.0, t.font_family)

            local badge_w = ui.measure_text(item.badge, 9, t.font_family) + 12
            local badge_x = cx + card_w - badge_w - 12
            ui.fill_rounded_rect(badge_x, cy + 10, badge_w, 18, 4, 0.14, 0.16, 0.22, 0.90)
            ui.draw_text(item.badge, badge_x + 6, cy + 13, 9, 0.8, 0.85, 0.95, 0.9, t.font_family)

            local title_str = item.title
            while #title_str > 4 and ui.measure_text(title_str, 11, t.font_family) > (card_w - 28) do
                title_str = title_str:sub(1, -2)
            end
            if title_str ~= item.title then
                title_str = title_str .. "..."
            end

            ui.draw_text(title_str, cx + 14, cy + card_h - 26, 11, 0.92, 0.92, 0.96, is_sel and 1.0 or 0.65,
                t.font_family)
        end
    end

    if active_target_hwnd and active_rect and wm.create_thumbnail then
        if active_thumb_hwnd ~= active_target_hwnd then
            cleanup_thumbnail()
            active_thumb = wm.create_thumbnail(active_target_hwnd)
            active_thumb_hwnd = active_target_hwnd
        end
        if active_thumb then
            wm.update_thumbnail(active_thumb, active_rect[1], active_rect[2], active_rect[3], active_rect[4], 255)
        end
    else
        cleanup_thumbnail()
    end
end

return alttab