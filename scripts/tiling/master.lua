local master = {}
master.name = "master"

local function ensure_structure(ws)
    if not ws.columns or #ws.columns == 0 then
        ws.columns = {{
            width = 0.55,
            windows = {}
        }, {
            width = 0.45,
            windows = {}
        }}
        return
    end

    local all_wins = {}
    for _, col in ipairs(ws.columns) do
        for _, w in ipairs(col.windows) do
            table.insert(all_wins, w)
        end
    end

    local m_ratio = (ws.columns[1] and ws.columns[1].width) or 0.55
    ws.columns = {{
        width = m_ratio,
        windows = {}
    }, {
        width = 1.0 - m_ratio,
        windows = {}
    }}

    if #all_wins > 0 then
        table.insert(ws.columns[1].windows, all_wins[1])
        for i = 2, #all_wins do
            table.insert(ws.columns[2].windows, all_wins[i])
        end
    end
end

function master.clean_columns(ws, is_valid_fn)
    ensure_structure(ws)
    local valid_m = {}
    for _, w in ipairs(ws.columns[1].windows) do
        if is_valid_fn(w) then
            table.insert(valid_m, w)
        end
    end
    ws.columns[1].windows = valid_m

    local valid_s = {}
    for _, w in ipairs(ws.columns[2].windows) do
        if is_valid_fn(w) then
            table.insert(valid_s, w)
        end
    end
    ws.columns[2].windows = valid_s

    if #ws.columns[1].windows == 0 and #ws.columns[2].windows > 0 then
        table.insert(ws.columns[1].windows, table.remove(ws.columns[2].windows, 1))
    end
end

function master.arrange(ws, wx, wy, ww, wh, cfg, focused_hwnd, overview_active)
    local targets = {}
    ensure_structure(ws)

    local m_wins = ws.columns[1].windows
    local s_wins = ws.columns[2].windows
    local total_wins = #m_wins + #s_wins

    if total_wins == 0 then
        return targets, 0.0, 0.0, 0.0
    end

    local is_smart = cfg.smart_gaps and (total_wins == 1) and not overview_active
    local gaps_in = is_smart and 0 or cfg.gaps_in
    local gaps_out = is_smart and 0 or cfg.gaps_out

    local avail_w = ww - (gaps_out * 2)
    local avail_h = wh - (gaps_out * 2)

    if #s_wins == 0 then
        targets[m_wins[1]] = {
            world_x = wx + gaps_out,
            y = wy + gaps_out,
            w = avail_w,
            h = avail_h
        }
        return targets, 0.0, 0.0, avail_w
    end

    local m_ratio = ws.columns[1].width or 0.55
    local m_w = math.floor((avail_w - gaps_in) * m_ratio)
    local s_w = avail_w - gaps_in - m_w

    targets[m_wins[1]] = {
        world_x = wx + gaps_out,
        y = wy + gaps_out,
        w = m_w,
        h = avail_h
    }

    local num_s = #s_wins
    local s_gap_total = (num_s - 1) * gaps_in
    local each_h = math.floor((avail_h - s_gap_total) / num_s)
    local cur_sy = wy + gaps_out
    local sx = wx + gaps_out + m_w + gaps_in

    for i, hwnd in ipairs(s_wins) do
        local h = (i == num_s) and (wy + gaps_out + avail_h - cur_sy) or each_h
        targets[hwnd] = {
            world_x = sx,
            y = cur_sy,
            w = s_w,
            h = h
        }
        cur_sy = cur_sy + h + gaps_in
    end

    return targets, 0.0, 0.0, ww
end

function master.add_window(ws, hwnd, focused_hwnd, default_width)
    ensure_structure(ws)
    if #ws.columns[1].windows == 0 then
        table.insert(ws.columns[1].windows, hwnd)
    else
        table.insert(ws.columns[2].windows, 1, hwnd)
    end
end

function master.remove_window(ws, hwnd)
    ensure_structure(ws)
    local removed_from = nil

    for i, w in ipairs(ws.columns[1].windows) do
        if w == hwnd then
            table.remove(ws.columns[1].windows, i)
            removed_from = "master"
            break
        end
    end

    if not removed_from then
        for i, w in ipairs(ws.columns[2].windows) do
            if w == hwnd then
                table.remove(ws.columns[2].windows, i)
                removed_from = "stack"
                break
            end
        end
    end

    if #ws.columns[1].windows == 0 and #ws.columns[2].windows > 0 then
        table.insert(ws.columns[1].windows, table.remove(ws.columns[2].windows, 1))
    end

    if #ws.columns[1].windows > 0 then
        return ws.columns[1].windows[1]
    end
    return nil
end

function master.focus_direction(ws, focused_hwnd, dir)
    ensure_structure(ws)
    local m_wins = ws.columns[1].windows
    local s_wins = ws.columns[2].windows

    local in_master = (#m_wins > 0 and m_wins[1] == focused_hwnd)
    local s_idx = nil

    if not in_master then
        for i, w in ipairs(s_wins) do
            if w == focused_hwnd then
                s_idx = i
                break
            end
        end
    end

    if dir == "right" and in_master and #s_wins > 0 then
        return s_wins[1]
    elseif dir == "left" and not in_master and #m_wins > 0 then
        return m_wins[1]
    elseif dir == "down" and s_idx and s_idx < #s_wins then
        return s_wins[s_idx + 1]
    elseif dir == "up" and s_idx and s_idx > 1 then
        return s_wins[s_idx - 1]
    end
    return nil
end

function master.cycle_preset(ws, focused_hwnd)
    ensure_structure(ws)
    local presets = {0.50, 0.60, 0.70}
    local cur = ws.columns[1].width or 0.55
    local next_r = presets[1]

    for i, p in ipairs(presets) do
        if math.abs(cur - p) < 0.04 then
            next_r = presets[(i % #presets) + 1]
            break
        end
    end
    ws.columns[1].width = next_r
    ws.columns[2].width = 1.0 - next_r
end

return master
