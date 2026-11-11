local ribbon = {}
ribbon.name = "ribbon"

function ribbon.clean_columns(ws, is_window_valid_fn)
    local cleaned = {}
    for _, col in ipairs(ws.columns) do
        local valid_wins = {}
        for _, hwnd in ipairs(col.windows) do
            if is_window_valid_fn(hwnd) then
                table.insert(valid_wins, hwnd)
            end
        end
        if #valid_wins > 0 then
            col.windows = valid_wins
            table.insert(cleaned, col)
        end
    end
    ws.columns = cleaned
end

function ribbon.arrange(ws, wx, wy, ww, wh, cfg, focused_hwnd, overview_active)
    local targets = {}
    local cols = ws.columns
    if not cols or #cols == 0 then
        return targets, 0.0, 0.0, 0.0
    end

    local is_smart = cfg.smart_gaps and (#cols == 1 and #cols[1].windows == 1) and not overview_active
    local gaps_in = is_smart and 0 or cfg.gaps_in
    local gaps_out = is_smart and 0 or cfg.gaps_out

    local avail_w = ww - (gaps_out * 2)
    local avail_h = wh - (gaps_out * 2)
    local cur_x = wx + gaps_out

    for _, col in ipairs(cols) do
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

            targets[hwnd] = {
                world_x = cur_x,
                y = cur_y,
                w = col_w,
                h = h
            }
            cur_y = cur_y + h + gaps_in
        end
        cur_x = cur_x + col_w + gaps_in
    end

    local total_w = cur_x - gaps_in + gaps_out
    local max_cam_x = math.max(0, (total_w - gaps_in + gaps_out - wx) - ww)

    local target_cam_x = nil
    if focused_hwnd and targets[focused_hwnd] then
        local target = targets[focused_hwnd]
        target_cam_x = (target.world_x - wx) - math.floor((ww - target.w) / 2)
        target_cam_x = math.max(0, math.min(max_cam_x, target_cam_x))
    end

    return targets, target_cam_x, max_cam_x, total_w
end

function ribbon.add_window(ws, hwnd, focused_hwnd, default_width)
    local active_col_idx = nil
    if focused_hwnd then
        for c_idx, col in ipairs(ws.columns) do
            for _, w in ipairs(col.windows) do
                if w == focused_hwnd then
                    active_col_idx = c_idx
                    break
                end
            end
            if active_col_idx then
                break
            end
        end
    end

    local new_col = {
        width = default_width or 1.0,
        windows = {hwnd}
    }

    if active_col_idx and active_col_idx <= #ws.columns then
        table.insert(ws.columns, active_col_idx + 1, new_col)
    else
        table.insert(ws.columns, new_col)
    end
end

function ribbon.remove_window(ws, hwnd)
    local found_col, found_row = nil, nil
    for c_idx, col in ipairs(ws.columns) do
        for r_idx, w in ipairs(col.windows) do
            if w == hwnd then
                found_col = c_idx
                found_row = r_idx
                break
            end
        end
        if found_col then
            break
        end
    end

    if not found_col then
        return nil
    end

    local col = ws.columns[found_col]
    table.remove(col.windows, found_row)
    if #col.windows == 0 then
        table.remove(ws.columns, found_col)
    end

    local next_col = ws.columns[found_col] or ws.columns[found_col - 1]
    if next_col and #next_col.windows > 0 then
        return next_col.windows[1]
    end
    return nil
end

function ribbon.focus_direction(ws, focused_hwnd, dir)
    local col_idx, row_idx = nil, nil
    for c_idx, col in ipairs(ws.columns) do
        for r_idx, w in ipairs(col.windows) do
            if w == focused_hwnd then
                col_idx = c_idx
                row_idx = r_idx
                break
            end
        end
        if col_idx then
            break
        end
    end

    if not col_idx then
        return nil
    end

    if dir == "left" and col_idx > 1 then
        local prev_col = ws.columns[col_idx - 1]
        return prev_col.windows[math.min(row_idx, #prev_col.windows)]
    elseif dir == "right" and col_idx < #ws.columns then
        local next_col = ws.columns[col_idx + 1]
        return next_col.windows[math.min(row_idx, #next_col.windows)]
    elseif dir == "up" and row_idx > 1 then
        return ws.columns[col_idx].windows[row_idx - 1]
    elseif dir == "down" and row_idx < #ws.columns[col_idx].windows then
        return ws.columns[col_idx].windows[row_idx + 1]
    end
    return nil
end

function ribbon.move_column(ws, focused_hwnd, dir)
    local col_idx = nil
    for c_idx, col in ipairs(ws.columns) do
        for _, w in ipairs(col.windows) do
            if w == focused_hwnd then
                col_idx = c_idx
                break
            end
        end
        if col_idx then
            break
        end
    end

    if not col_idx then
        return false
    end

    if dir == "left" and col_idx > 1 then
        ws.columns[col_idx], ws.columns[col_idx - 1] = ws.columns[col_idx - 1], ws.columns[col_idx]
        return true
    elseif dir == "right" and col_idx < #ws.columns then
        ws.columns[col_idx], ws.columns[col_idx + 1] = ws.columns[col_idx + 1], ws.columns[col_idx]
        return true
    end
    return false
end

function ribbon.cycle_preset(ws, focused_hwnd)
    local target_col = nil
    for _, col in ipairs(ws.columns) do
        for _, w in ipairs(col.windows) do
            if w == focused_hwnd then
                target_col = col
                break
            end
        end
        if target_col then
            break
        end
    end

    if not target_col then
        return
    end

    local presets = {1.0, 0.666, 0.50}
    local next_ratio = presets[1]
    local cur_w = target_col.width or 1.0

    for i, p in ipairs(presets) do
        if math.abs(cur_w - p) < 0.05 then
            next_ratio = presets[(i % #presets) + 1]
            break
        end
    end
    target_col.width = next_ratio
end

return ribbon
