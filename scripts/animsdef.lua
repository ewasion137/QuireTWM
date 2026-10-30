local anims = {}

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
        if t == 0.0 then return 0.0 end
        if t == 1.0 then return 1.0 end
        return math.pow(2.0, -10.0 * t) * math.sin((t * 10.0 - 0.75) * ((2.0 * math.pi) / 3.0)) + 1.0
    end
}

anims.idle = {
    pulse = function(time, base_color)
        local wave = (math.sin(time * 3.5) + 1.0) * 0.5
        local alpha = base_color[4] * (0.65 + wave * 0.35)
        return { base_color[1], base_color[2], base_color[3], alpha }, 0, 0
    end,

    shake = function(time, base_color)
        local ox = math.sin(time * 30.0) * 1.5
        local oy = math.cos(time * 26.0) * 1.5
        return base_color, math.floor(ox), math.floor(oy)
    end,

    flash = function(time, base_color)
        local burst = math.sin(time * 6.0)
        local boost = (burst > 0.7) and 0.3 or 0.0
        local r = math.min(1.0, base_color[1] + boost)
        local g = math.min(1.0, base_color[2] + boost)
        local b = math.min(1.0, base_color[3] + boost)
        return { r, g, b, base_color[4] }, 0, 0
    end,

    heartbeat = function(time, base_color)
        local cycle = time % 1.2
        local scale = 0.0
        if cycle < 0.15 then
            scale = math.sin((cycle / 0.15) * math.pi) * 0.4
        elseif cycle > 0.22 and cycle < 0.37 then
            scale = math.sin(((cycle - 0.22) / 0.15) * math.pi) * 0.2
        end
        local alpha = math.min(1.0, base_color[4] + scale)
        return { base_color[1], base_color[2], base_color[3], alpha }, 0, 0
    end,

    wobble = function(time, base_color)
        local ox = math.sin(time * 4.0) * 2.0
        local oy = math.cos(time * 3.0) * 1.5
        return base_color, math.floor(ox), math.floor(oy)
    end
}

function anims.compute_alt_tab_zoom(x, y, w, h, factor, sw, sh)
    local cx = sw * 0.5
    local cy = sh * 0.5
    local win_cx = x + (w * 0.5)
    local win_cy = y + (h * 0.5)

    local target_w = math.floor(w * factor)
    local target_h = math.floor(h * factor)
    local target_cx = cx + (win_cx - cx) * factor
    local target_cy = cy + (win_cy - cy) * factor

    return math.floor(target_cx - target_w * 0.5),
           math.floor(target_cy - target_h * 0.5),
           target_w,
           target_h
end

function anims.calc_close_geometry(mode, progress, x, y, w, h, sh)
    local alpha = 1.0 - progress

    if mode == "slide" then
        return x, y + math.floor(progress * progress * (sh - y)), w, h, alpha
    elseif mode == "scale" or mode == "zoom" then
        local sf = 1.0 - progress
        local nw = math.floor(w * sf)
        local nh = math.floor(h * sf)
        local nx = x + math.floor((w - nw) * 0.5)
        local ny = y + math.floor((h - nh) * 0.5)
        return nx, ny, nw, nh, alpha
    elseif mode == "fold" or mode == "curtain" then
        local nw = math.floor(w * (1.0 - progress))
        local nx = x + math.floor((w - nw) * 0.5)
        return nx, y, nw, h, alpha
    end

    return x, y, w, h, alpha
end

return anims