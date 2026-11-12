local infinite = {}
infinite.name = "infinite"

local function sync_columns(ws)
    local cols = {}
    if ws.infinite_nodes then
        for hwnd, _ in pairs(ws.infinite_nodes) do
            table.insert(cols, {
                width = 1.0,
                windows = {hwnd}
            })
        end
    end
    ws.columns = cols
end

local function ensure_nodes(ws, wx, wy, ww, wh, cfg)
    if ws.infinite_nodes then
        return
    end

    ws.infinite_nodes = {}
    if not ws.columns or #ws.columns == 0 then
        return
    end

    local default_w = math.floor(ww * 0.55)
    local default_h = math.floor(wh * 0.60)
    local cur_x = wx + cfg.gaps_out
    local cur_y = wy + cfg.gaps_out

    for _, col in ipairs(ws.columns) do
        for _, hwnd in ipairs(col.windows) do
            ws.infinite_nodes[hwnd] = {
                x = cur_x,
                y = cur_y,
                w = default_w,
                h = default_h
            }
            cur_x = cur_x + default_w + cfg.gaps_in
        end
    end
    sync_columns(ws)
end

function infinite.clean_columns(ws, is_valid_fn)
    if not ws.infinite_nodes then
        sync_columns(ws)
        return
    end

    for hwnd, _ in pairs(ws.infinite_nodes) do
        if not is_valid_fn(hwnd) then
            ws.infinite_nodes[hwnd] = nil
        end
    end
    sync_columns(ws)
end

function infinite.arrange(ws, wx, wy, ww, wh, cfg, focused_hwnd, overview_active)
    ensure_nodes(ws, wx, wy, ww, wh, cfg)
    local targets = {}
    if not ws.infinite_nodes then
        return targets, 0.0, 0.0, 0.0, 0.0
    end

    local count = 0
    local min_x, max_x = 999999, -999999
    for hwnd, node in pairs(ws.infinite_nodes) do
        count = count + 1
        targets[hwnd] = {
            world_x = node.x,
            y = node.y,
            w = node.w,
            h = node.h
        }
        if node.x < min_x then min_x = node.x end
        if (node.x + node.w) > max_x then max_x = node.x + node.w end
    end

    if count == 0 then
        return targets, 0.0, 0.0, 0.0, 0.0
    end

    local total_w = math.max(ww, max_x - min_x)
    local target_cam_x = 0.0
    local target_cam_y = 0.0

    if focused_hwnd and ws.infinite_nodes[focused_hwnd] then
        local node = ws.infinite_nodes[focused_hwnd]
        target_cam_x = (node.x - wx) - math.floor((ww - node.w) * 0.5)
        target_cam_y = (node.y - wy) - math.floor((wh - node.h) * 0.5)
    end

    return targets, target_cam_x, total_w, total_w, target_cam_y
end

function infinite.add_window(ws, hwnd, focused_hwnd, default_width)
    ws.infinite_nodes = ws.infinite_nodes or {}
    local wx, wy, ww, wh = wm.get_work_area()
    local cfg = Quire.config

    local def_w = math.floor(ww * (default_width or 0.55))
    local def_h = math.floor(wh * 0.60)

    local target_x = wx + cfg.gaps_out
    local target_y = wy + cfg.gaps_out

    if focused_hwnd and ws.infinite_nodes[focused_hwnd] then
        local f_node = ws.infinite_nodes[focused_hwnd]
        target_x = f_node.x + f_node.w + cfg.gaps_in
        target_y = f_node.y
    end

    ws.infinite_nodes[hwnd] = {
        x = target_x,
        y = target_y,
        w = def_w,
        h = def_h
    }
    sync_columns(ws)
end

function infinite.remove_window(ws, hwnd)
    if not ws.infinite_nodes or not ws.infinite_nodes[hwnd] then
        return nil
    end

    ws.infinite_nodes[hwnd] = nil
    sync_columns(ws)

    for next_hwnd, _ in pairs(ws.infinite_nodes) do
        return next_hwnd
    end
    return nil
end

function infinite.focus_direction(ws, focused_hwnd, dir)
    if not ws.infinite_nodes or not focused_hwnd or not ws.infinite_nodes[focused_hwnd] then
        return nil
    end

    local cur = ws.infinite_nodes[focused_hwnd]
    local cx = cur.x + cur.w * 0.5
    local cy = cur.y + cur.h * 0.5

    local best_hwnd = nil
    local best_dist = 99999999.0

    for hwnd, node in pairs(ws.infinite_nodes) do
        if hwnd ~= focused_hwnd then
            local lx = node.x + node.w * 0.5
            local ly = node.y + node.h * 0.5
            local dx = lx - cx
            local dy = ly - cy

            local valid = false
            if dir == "left" and dx < -10 then valid = true
            elseif dir == "right" and dx > 10 then valid = true
            elseif dir == "up" and dy < -10 then valid = true
            elseif dir == "down" and dy > 10 then valid = true end

            if valid then
                local dist = (dir == "left" or dir == "right")
                    and (math.abs(dx) + math.abs(dy) * 2.0)
                    or (math.abs(dy) + math.abs(dx) * 2.0)

                if dist < best_dist then
                    best_dist = dist
                    best_hwnd = hwnd
                end
            end
        end
    end
    return best_hwnd
end

function infinite.cycle_preset(ws, focused_hwnd)
    if not ws.infinite_nodes or not focused_hwnd or not ws.infinite_nodes[focused_hwnd] then
        return
    end

    local _, _, ww, wh = wm.get_work_area()
    local node = ws.infinite_nodes[focused_hwnd]
    local presets = {
        { w = math.floor(ww * 0.50), h = math.floor(wh * 0.55) },
        { w = math.floor(ww * 0.65), h = math.floor(wh * 0.70) },
        { w = math.floor(ww * 0.80), h = math.floor(wh * 0.85) }
    }

    local next_p = presets[1]
    for i, p in ipairs(presets) do
        if math.abs(node.w - p.w) < 40 then
            next_p = presets[(i % #presets) + 1]
            break
        end
    end

    node.w = next_p.w
    node.h = next_p.h
end

return infinite