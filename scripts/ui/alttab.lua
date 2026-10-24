local alttab = {}

Quire.alttab_active = false
Quire.alttab_index = 1
Quire.alttab_windows = {}

local function is_valid(hwnd)
    return wm.is_window_visible(hwnd)
end

function alttab.action(action_type)
    if action_type == "next" then
        if not Quire.alttab_active then
            Quire.alttab_active = true
            Quire.alttab_windows = {}

            -- Собираем видимые окна с текущей ленты
            local ws = Quire.workspaces[Quire.current_workspace]
            if ws and ws.columns then
                for _, col in ipairs(ws.columns) do
                    for _, hwnd in ipairs(col) do
                        if is_valid(hwnd) then
                            table.insert(Quire.alttab_windows, hwnd)
                        end
                    end
                end
            end

            -- Добавляем плавающие окна
            for hwnd, _ in pairs(Quire.floating_windows) do
                if is_valid(hwnd) then
                    table.insert(Quire.alttab_windows, hwnd)
                end
            end

            Quire.alttab_index = (#Quire.alttab_windows >= 2) and 2 or 1
        else
            local count = #Quire.alttab_windows
            if count > 0 then
                Quire.alttab_index = (Quire.alttab_index % count) + 1
            end
        end
    elseif action_type == "prev" then
        if Quire.alttab_active then
            local count = #Quire.alttab_windows
            if count > 0 then
                Quire.alttab_index = (Quire.alttab_index - 2 + count) % count + 1
            end
        end
    elseif action_type == "commit" then
        if Quire.alttab_active then
            local target = Quire.alttab_windows[Quire.alttab_index]
            if target and is_valid(target) then
                wm.focus_window(target)
            end
            Quire.alttab_active = false
            Quire.alttab_windows = {}
        end
    elseif action_type == "cancel" then
        Quire.alttab_active = false
        Quire.alttab_windows = {}
    end
end

function alttab.draw()
    if not Quire.alttab_active then return end
    local count = #Quire.alttab_windows
    if count == 0 then return end

    local sw, sh = wm.get_screen_size()
    local t = Quire.theme

    local item_w, item_h, gap_x, padding = 120, 90, 10, 16
    local modal_w = math.max(300, (count * item_w) + ((count - 1) * gap_x) + (padding * 2))
    local modal_h = item_h + (padding * 2)
    local modal_x = math.floor((sw - modal_w) / 2)
    local modal_y = math.floor((sh - modal_h) / 2)

    ui.fill_rounded_rect(modal_x, modal_y, modal_w, modal_h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4])
    ui.draw_rounded_rect(modal_x, modal_y, modal_w, modal_h, t.rounding, t.border_color[1], t.border_color[2], t.border_color[3], t.border_color[4], t.border_size)

    local start_x = modal_x + math.floor((modal_w - ((count * item_w) + ((count - 1) * gap_x))) / 2)

    for i = 1, count do
        local hwnd = Quire.alttab_windows[i]
        if hwnd and is_valid(hwnd) then
            local item_x = start_x + (i - 1) * (item_w + gap_x)
            local item_y = modal_y + padding
            local is_selected = (i == Quire.alttab_index)

            if is_selected then
                ui.fill_rounded_rect(item_x, item_y, item_w, item_h, t.rounding - 2, t.accent_color[1], t.accent_color[2], t.accent_color[3], 0.25)
                ui.draw_rounded_rect(item_x, item_y, item_w, item_h, t.rounding - 2, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 1.0, 1)
            end

            local raw_title = wm.get_window_title(hwnd)
            local label = (#raw_title > 16) and (raw_title:sub(1, 13) .. "...") or raw_title
            local text_w = ui.measure_text(label, 10, t.font_family)
            local lx = item_x + math.floor((item_w - text_w) / 2)
            local ly = item_y + item_h - 22

            local tc = is_selected and t.text_color or t.text_dim
            ui.draw_text(label, lx, ly, 10, tc[1], tc[2], tc[3], tc[4], t.font_family)
        end
    end
end

return alttab