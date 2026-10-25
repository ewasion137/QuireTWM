local alttab = {}

Quire.alttab_active = false
Quire.alttab_index = 1
Quire.alttab_windows = {}

local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

function alttab.action(action_type)
    local ws = Quire.workspaces[Quire.current_workspace]

    if action_type == "next" or action_type == "prev" then
        if not Quire.alttab_active then
            Quire.alttab_active = true
            Quire.alttab_windows = {}

            if ws and ws.columns then
                for _, col in ipairs(ws.columns) do
                    for _, hwnd in ipairs(col.windows) do
                        if is_valid(hwnd) then
                            table.insert(Quire.alttab_windows, hwnd)
                        end
                    end
                end
            end

            for hwnd, _ in pairs(Quire.floating_windows) do
                if is_valid(hwnd) then
                    table.insert(Quire.alttab_windows, hwnd)
                end
            end

            Quire.alttab_index = (#Quire.alttab_windows >= 2) and 2 or 1
        else
            local count = #Quire.alttab_windows
            if count > 0 then
                if action_type == "next" then
                    Quire.alttab_index = (Quire.alttab_index % count) + 1
                else
                    Quire.alttab_index = (Quire.alttab_index - 2 + count) % count + 1
                end
            end
        end

        local target = Quire.alttab_windows[Quire.alttab_index]
        if target and is_valid(target) then
            Quire.focused_window = target
            Quire.retile()
        end

    elseif action_type == "commit" then
        if Quire.alttab_active then
            local target = Quire.alttab_windows[Quire.alttab_index]
            if target and is_valid(target) then
                Quire.focused_window = target
                wm.focus_window(target)
                Quire.retile()
            end
            Quire.alttab_active = false
            Quire.alttab_windows = {}
        end
    elseif action_type == "cancel" then
        Quire.alttab_active = false
        Quire.alttab_windows = {}
        Quire.retile()
    end
end

function alttab.draw()
    if not Quire.alttab_active then return end
    local count = #Quire.alttab_windows
    if count == 0 then return end

    local sw, sh = wm.get_screen_size()
    local t = Quire.theme
    local accent = Quire.config.border_active or t.active_border_color

    ui.fill_rect(0, 0, sw, sh, 0.02, 0.02, 0.04, 0.70)

    local card_w = math.min(240, math.floor((sw - 120) / count))
    local card_h = math.floor(card_w * 0.65)
    local gap_x = 16

    local total_w = (count * card_w) + ((count - 1) * gap_x)
    local start_x = math.floor((sw - total_w) / 2)
    local start_y = math.floor((sh - card_h) / 2)

    for i = 1, count do
        local hwnd = Quire.alttab_windows[i]
        if hwnd and is_valid(hwnd) then
            local cx = start_x + (i - 1) * (card_w + gap_x)
            local cy = start_y
            local is_sel = (i == Quire.alttab_index)

            if is_sel then
                ui.fill_rounded_rect(cx - 4, cy - 4, card_w + 8, card_h + 8, t.rounding + 2, accent[1], accent[2], accent[3], 0.20)
                ui.fill_rounded_rect(cx, cy, card_w, card_h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], 0.95)
                ui.draw_rounded_rect(cx, cy, card_w, card_h, t.rounding, accent[1], accent[2], accent[3], 1.0, 2)
            else
                ui.fill_rounded_rect(cx, cy, card_w, card_h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], 0.75)
                ui.draw_rounded_rect(cx, cy, card_w, card_h, t.rounding, t.border_color[1], t.border_color[2], t.border_color[3], 0.4, 1)
            end

            local raw_title = wm.get_window_title(hwnd)
            local label = (#raw_title > 18) and (raw_title:sub(1, 15) .. "...") or raw_title
            local text_w = ui.measure_text(label, 11, t.font_family)
            local lx = cx + math.floor((card_w - text_w) / 2)
            local ly = cy + math.floor((card_h - 16) / 2)

            local tc = is_sel and t.text_color or t.text_dim
            ui.draw_text(label, lx, ly, 11, tc[1], tc[2], tc[3], tc[4], t.font_family)

            local idx_str = tostring(i)
            ui.draw_text(idx_str, cx + 12, cy + 10, 10, tc[1], tc[2], tc[3], 0.4, t.font_family)
        end
    end
end

return alttab