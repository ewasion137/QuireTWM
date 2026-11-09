local anims = {}

local cached_color = {1.0, 1.0, 1.0, 1.0}

local function solve_bezier_t(x1, x2, x)
    local t = x
    for _ = 1, 5 do
        local cx = 3.0 * (1.0 - t) * (1.0 - t) * t * x1 + 3.0 * (1.0 - t) * t * t * x2 + t * t * t
        local dx = 3.0 * (1.0 - t) * (1.0 - t) * x1 + 6.0 * (1.0 - t) * t * (x2 - x1) + 3.0 * t * t * (1.0 - x2)
        if math.abs(dx) < 1e-6 then
            break
        end
        t = t - (cx - x) / dx
        t = math.max(0.0, math.min(1.0, t))
    end
    return t
end

function anims.bezier(x1, y1, x2, y2)
    return function(t)
        if t <= 0.0 then
            return 0.0
        end
        if t >= 1.0 then
            return 1.0
        end
        local bt = solve_bezier_t(x1, x2, t)
        return 3.0 * (1.0 - bt) * (1.0 - bt) * bt * y1 + 3.0 * (1.0 - bt) * bt * bt * y2 + bt * bt * bt
    end
end

anims.easings = {
    linear = function(t)
        return t
    end,

    ease_in = function(t)
        return t * t * t
    end,

    ease_out = function(t)
        local inv = 1.0 - t
        return 1.0 - inv * inv * inv
    end,

    ease_in_out = function(t)
        if t < 0.5 then
            return 4.0 * t * t * t
        else
            local f = (2.0 * t) - 2.0
            return 0.5 * f * f * f + 1.0
        end
    end,

    expo_out = function(t)
        return (t >= 1.0) and 1.0 or (1.0 - 2.0 ^ (-10.0 * t))
    end,

    circ_out = function(t)
        local inv = t - 1.0
        return math.sqrt(math.max(0.0, 1.0 - inv * inv))
    end,

    sine = function(t)
        return math.sin((t * math.pi) * 0.5)
    end,

    back = function(t)
        local c1 = 1.70158
        local c3 = c1 + 1.0
        local inv = t - 1.0
        return 1.0 + c3 * inv * inv * inv + c1 * inv * inv
    end,

    bounce = function(t)
        local n1 = 7.5625
        local d1 = 2.75
        if t < (1.0 / d1) then
            return n1 * t * t
        elseif t < (2.0 / d1) then
            t = t - (1.5 / d1)
            return n1 * t * t + 0.75
        elseif t < (2.5 / d1) then
            t = t - (2.25 / d1)
            return n1 * t * t + 0.9375
        else
            t = t - (2.625 / d1)
            return n1 * t * t + 0.984375
        end
    end,

    elastic = function(t)
        if t <= 0.0 then
            return 0.0
        end
        if t >= 1.0 then
            return 1.0
        end
        return 1.0 - (2.0 ^ (-4.0 * t)) * math.cos(t * math.pi * 1.5)
    end
}

local function hsv_to_rgb(h, s, v)
    local c = v * s
    local x = c * (1.0 - math.abs((h * 6.0) % 2.0 - 1.0))
    local m = v - c
    local r, g, b = m, m, m
    local hi = math.floor(h * 6.0) % 6
    if hi == 0 then
        r, g, b = c + m, x + m, m
    elseif hi == 1 then
        r, g, b = x + m, c + m, m
    elseif hi == 2 then
        r, g, b = m, c + m, x + m
    elseif hi == 3 then
        r, g, b = m, x + m, c + m
    elseif hi == 4 then
        r, g, b = x + m, m, c + m
    elseif hi == 5 then
        r, g, b = c + m, m, x + m
    end
    return r, g, b
end

anims.idle = {
    pulse = function(time, base_color)
        local wave = (math.sin(time * 3.2) + 1.0) * 0.5
        local alpha = (base_color[4] or 1.0) * (0.60 + wave * 0.40)
        cached_color[1] = base_color[1]
        cached_color[2] = base_color[2]
        cached_color[3] = base_color[3]
        cached_color[4] = alpha
        return cached_color, 0, 0
    end,

    breathe = function(time, base_color)
        local val = (math.exp(math.sin(time * 2.2)) - 0.36787944) * 0.425
        local alpha = (base_color[4] or 1.0) * (0.50 + val * 0.50)
        cached_color[1] = base_color[1]
        cached_color[2] = base_color[2]
        cached_color[3] = base_color[3]
        cached_color[4] = alpha
        return cached_color, 0, 0
    end,

    rainbow = function(time, base_color)
        local hue = (time * 0.25) % 1.0
        local r, g, b = hsv_to_rgb(hue, 0.85, 1.0)
        cached_color[1] = r
        cached_color[2] = g
        cached_color[3] = b
        cached_color[4] = base_color[4] or 1.0
        return cached_color, 0, 0
    end,

    neon = function(time, base_color)
        local pulse = math.sin(time * 8.0) * 0.15
        local spike = (math.sin(time * 24.0) > 0.92) and 0.25 or 0.0
        local alpha = math.min(1.0, (base_color[4] or 1.0) + pulse + spike)
        cached_color[1] = math.min(1.0, base_color[1] + spike * 0.5)
        cached_color[2] = math.min(1.0, base_color[2] + spike * 0.5)
        cached_color[3] = math.min(1.0, base_color[3] + spike * 0.5)
        cached_color[4] = alpha
        return cached_color, 0, 0
    end,

    heartbeat = function(time, base_color)
        local cycle = time % 1.15
        local scale = 0.0
        if cycle < 0.14 then
            scale = math.sin((cycle / 0.14) * math.pi) * 0.38
        elseif cycle > 0.20 and cycle < 0.34 then
            scale = math.sin(((cycle - 0.20) / 0.14) * math.pi) * 0.20
        end
        local alpha = math.min(1.0, (base_color[4] or 1.0) + scale)
        cached_color[1] = base_color[1]
        cached_color[2] = base_color[2]
        cached_color[3] = base_color[3]
        cached_color[4] = alpha
        return cached_color, 0, 0
    end,

    flash = function(time, base_color)
        local burst = math.sin(time * 6.0)
        local boost = (burst > 0.75) and 0.25 or 0.0
        cached_color[1] = math.min(1.0, base_color[1] + boost)
        cached_color[2] = math.min(1.0, base_color[2] + boost)
        cached_color[3] = math.min(1.0, base_color[3] + boost)
        cached_color[4] = base_color[4] or 1.0
        return cached_color, 0, 0
    end,

    shake = function(time, base_color)
        local ox = math.sin(time * 28.0) * 1.5
        local oy = math.cos(time * 24.0) * 1.5
        return base_color, math.floor(ox), math.floor(oy)
    end,

    wobble = function(time, base_color)
        local ox = math.sin(time * 3.8) * 2.0
        local oy = math.cos(time * 2.9) * 1.5
        return base_color, math.floor(ox), math.floor(oy)
    end
}

function anims.compute_alt_tab_zoom(x, y, w, h, factor, sw, sh)
    local cx = sw * 0.5
    local cy = sh * 0.5
    local win_cx = x + (w * 0.5)
    local win_cy = y + (h * 0.5)

    local target_w = math.max(10, math.floor(w * factor))
    local target_h = math.max(10, math.floor(h * factor))
    local target_cx = cx + (win_cx - cx) * factor
    local target_cy = cy + (win_cy - cy) * factor

    return math.floor(target_cx - target_w * 0.5), math.floor(target_cy - target_h * 0.5), target_w, target_h
end

function anims.calc_close_geometry(mode, progress, x, y, w, h, sh)
    local alpha = math.max(0.0, math.min(1.0, 1.0 - progress))

    if mode == "slide" then
        local offset_y = math.floor(progress * progress * (sh - y + 40))
        return x, y + offset_y, w, h, alpha

    elseif mode == "pop" then
        local sf = math.max(0.0, 1.0 - (progress * 0.15))
        local nw = math.max(1, math.floor(w * sf))
        local nh = math.max(1, math.floor(h * sf))
        local nx = x + math.floor((w - nw) * 0.5)
        local ny = y + math.floor((h - nh) * 0.5)
        return nx, ny, nw, nh, 1.0 - (progress * progress)

    elseif mode == "crt" then
        if progress < 0.60 then
            local p = progress / 0.60
            local nh = math.max(2, math.floor(h * (1.0 - p)))
            local ny = y + math.floor((h - nh) * 0.5)
            return x, ny, w, nh, 1.0
        else
            local p = (progress - 0.60) / 0.40
            local nw = math.max(2, math.floor(w * (1.0 - p)))
            local nx = x + math.floor((w - nw) * 0.5)
            local ny = y + math.floor(h * 0.5)
            return nx, ny, nw, 2, 1.0 - p
        end

    elseif mode == "scale" or mode == "zoom" then
        local sf = math.max(0.0, 1.0 - progress)
        local nw = math.max(1, math.floor(w * sf))
        local nh = math.max(1, math.floor(h * sf))
        local nx = x + math.floor((w - nw) * 0.5)
        local ny = y + math.floor((h - nh) * 0.5)
        return nx, ny, nw, nh, alpha

    elseif mode == "fold" or mode == "curtain" then
        local nw = math.max(1, math.floor(w * math.max(0.0, 1.0 - progress)))
        local nx = x + math.floor((w - nw) * 0.5)
        return nx, y, nw, h, alpha
    end

    return x, y, w, h, alpha
end

return anims
