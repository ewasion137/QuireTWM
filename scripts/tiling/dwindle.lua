local dwindle = {}
dwindle.name = "dwindle"

local function collect_leaves(node, list)
    if not node then
        return
    end
    if node.hwnd then
        table.insert(list, node)
        return
    end
    collect_leaves(node.first, list)
    collect_leaves(node.second, list)
end

local function sync_columns(ws)
    local leaves = {}
    collect_leaves(ws.dwindle_tree, leaves)
    local cols = {}
    for _, leaf in ipairs(leaves) do
        table.insert(cols, {
            width = 1.0,
            windows = {leaf.hwnd}
        })
    end
    ws.columns = cols
end

local function find_node_and_parent(curr, parent, hwnd)
    if not curr then
        return nil, nil
    end
    if curr.hwnd == hwnd then
        return curr, parent
    end
    local n, p = find_node_and_parent(curr.first, curr, hwnd)
    if n then
        return n, p
    end
    return find_node_and_parent(curr.second, curr, hwnd)
end

local function get_first_leaf(node)
    if not node then
        return nil
    end
    if node.hwnd then
        return node
    end
    return get_first_leaf(node.first) or get_first_leaf(node.second)
end

function dwindle.clean_columns(ws, is_valid_fn)
    if not ws.dwindle_tree then
        ws.columns = {}
        return
    end

    local leaves = {}
    collect_leaves(ws.dwindle_tree, leaves)

    for _, leaf in ipairs(leaves) do
        if not is_valid_fn(leaf.hwnd) then
            dwindle.remove_window(ws, leaf.hwnd)
        end
    end
    sync_columns(ws)
end

function dwindle.arrange(ws, wx, wy, ww, wh, cfg, focused_hwnd, overview_active)
    local targets = {}
    if not ws.dwindle_tree then
        return targets, 0.0, 0.0, 0.0
    end

    local leaves = {}
    collect_leaves(ws.dwindle_tree, leaves)
    local total_wins = #leaves
    if total_wins == 0 then
        return targets, 0.0, 0.0, 0.0
    end

    local is_smart = cfg.smart_gaps and (total_wins == 1) and not overview_active
    local gaps_in = is_smart and 0 or cfg.gaps_in
    local gaps_out = is_smart and 0 or cfg.gaps_out

    local ax = wx + gaps_out
    local ay = wy + gaps_out
    local aw = ww - (gaps_out * 2)
    local ah = wh - (gaps_out * 2)

    local function layout_node(node, x, y, w, h)
        node.rect = {
            x = x,
            y = y,
            w = w,
            h = h
        }
        if node.hwnd then
            targets[node.hwnd] = {
                world_x = x,
                y = y,
                w = w,
                h = h
            }
            return
        end

        local ratio = node.ratio or 0.5
        if node.split == "col" then
            local w1 = math.floor((w - gaps_in) * ratio)
            local w2 = w - gaps_in - w1
            layout_node(node.first, x, y, w1, h)
            layout_node(node.second, x + w1 + gaps_in, y, w2, h)
        else
            local h1 = math.floor((h - gaps_in) * ratio)
            local h2 = h - gaps_in - h1
            layout_node(node.first, x, y, w, h1)
            layout_node(node.second, x, y + h1 + gaps_in, w, h2)
        end
    end

    layout_node(ws.dwindle_tree, ax, ay, aw, ah)
    return targets, 0.0, 0.0, ww
end

function dwindle.add_window(ws, hwnd, focused_hwnd, default_width)
    if not ws.dwindle_tree then
        ws.dwindle_tree = {
            hwnd = hwnd
        }
        sync_columns(ws)
        return
    end

    local target_leaf = nil
    if focused_hwnd then
        target_leaf = find_node_and_parent(ws.dwindle_tree, nil, focused_hwnd)
    end
    if not target_leaf then
        target_leaf = get_first_leaf(ws.dwindle_tree)
    end

    if not target_leaf then
        ws.dwindle_tree = {
            hwnd = hwnd
        }
        sync_columns(ws)
        return
    end

    local split_dir = "col"
    if target_leaf.rect then
        if target_leaf.rect.w >= math.floor(target_leaf.rect.h * 1.15) then
            split_dir = "col"
        else
            split_dir = "row"
        end
    end

    local old_hwnd = target_leaf.hwnd
    target_leaf.hwnd = nil
    target_leaf.split = split_dir
    target_leaf.ratio = 0.5
    target_leaf.first = {
        hwnd = old_hwnd,
        rect = target_leaf.rect
    }
    target_leaf.second = {
        hwnd = hwnd
    }

    sync_columns(ws)
end

function dwindle.remove_window(ws, hwnd)
    if not ws.dwindle_tree then
        return nil
    end

    local target_leaf, parent = find_node_and_parent(ws.dwindle_tree, nil, hwnd)
    if not target_leaf then
        return nil
    end

    if not parent then
        ws.dwindle_tree = nil
        ws.columns = {}
        return nil
    end

    local sibling = (parent.first == target_leaf) and parent.second or parent.first
    local _, grand = find_node_and_parent(ws.dwindle_tree, nil, parent)

    if not grand then
        ws.dwindle_tree = sibling
    else
        if grand.first == parent then
            grand.first = sibling
        else
            grand.second = sibling
        end
    end

    sync_columns(ws)
    local next_leaf = get_first_leaf(ws.dwindle_tree)
    return next_leaf and next_leaf.hwnd or nil
end

function dwindle.focus_direction(ws, focused_hwnd, dir)
    if not ws.dwindle_tree or not focused_hwnd then
        return nil
    end

    local cur_leaf = find_node_and_parent(ws.dwindle_tree, nil, focused_hwnd)
    if not cur_leaf or not cur_leaf.rect then
        return nil
    end

    local cx = cur_leaf.rect.x + cur_leaf.rect.w * 0.5
    local cy = cur_leaf.rect.y + cur_leaf.rect.h * 0.5

    local leaves = {}
    collect_leaves(ws.dwindle_tree, leaves)

    local best_hwnd = nil
    local best_dist = 99999999.0

    for _, leaf in ipairs(leaves) do
        if leaf.hwnd ~= focused_hwnd and leaf.rect then
            local lx = leaf.rect.x + leaf.rect.w * 0.5
            local ly = leaf.rect.y + leaf.rect.h * 0.5
            local dx = lx - cx
            local dy = ly - cy

            local valid = false
            if dir == "left" and dx < -5 then
                valid = true
            elseif dir == "right" and dx > 5 then
                valid = true
            elseif dir == "up" and dy < -5 then
                valid = true
            elseif dir == "down" and dy > 5 then
                valid = true
            end

            if valid then
                local dist
                if dir == "left" or dir == "right" then
                    dist = math.abs(dx) + (math.abs(dy) * 2.2)
                else
                    dist = math.abs(dy) + (math.abs(dx) * 2.2)
                end

                if dist < best_dist then
                    best_dist = dist
                    best_hwnd = leaf.hwnd
                end
            end
        end
    end
    return best_hwnd
end

function dwindle.cycle_preset(ws, focused_hwnd)
    if not ws.dwindle_tree or not focused_hwnd then
        return
    end
    local _, parent = find_node_and_parent(ws.dwindle_tree, nil, focused_hwnd)
    if parent then
        local presets = {0.50, 0.60, 0.40}
        local cur = parent.ratio or 0.50
        local next_r = presets[1]
        for i, p in ipairs(presets) do
            if math.abs(cur - p) < 0.04 then
                next_r = presets[(i % #presets) + 1]
                break
            end
        end
        parent.ratio = next_r
    end
end

return dwindle
