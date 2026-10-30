local M = {}

local pi = math.pi
local sin = math.sin
local cos = math.cos
local exp = math.exp
local abs = math.abs

local function clamp(v, min_v, max_v)
    if v < min_v then return min_v end
    if v > max_v then return max_v end
    return v
end

M.easings = {
    linear = function(t)
        return clamp(t, 0.0, 1.0)
    end,

    ease_in = function(t)
        t = clamp(t, 0.0, 1.0)
        return t * t * t
    end,

    ease_out = function(t)
        t = clamp(t, 0.0, 1.0) - 1.0
        return t * t * t + 1.0
    end,

    ease_in_out = function(t)
        t = clamp(t, 0.0, 1.0)
        if t < 0.5 then
            return 4.0 * t * t * t
        else
            local f = (2.0 * t) - 2.0
            return 0.5 * f * f * f + 1.0
        end
    end,

    anticipation = function(t)
        t = clamp(t, 0.0, 1.0)
        local c = 2.70158
        return (c + 1.0) * t * t * t - c * t * t
    end,

    back_out = function(t)
        t = clamp(t, 0.0, 1.0) - 1.0
        local c = 1.70158
        return t * t * ((c + 1.0) * t + c) + 1.0
    end,

    elastic = function(t)
        t = clamp(t, 0.0, 1.0)
        if t == 0.0 or t == 1.0 then return t end
        local p = 0.3
        local s = p / 4.0
        return (2.0 ^ (-10.0 * t)) * sin((t - s) * (2.0 * pi) / p) + 1.0
    end,

    bounce = function(t)
        t = clamp(t, 0.0, 1.0)
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
    end
}

M.idle = {
    pulse = function(time, speed)
        return (sin(time * (speed or 3.0)) + 1.0) * 0.5
    end,

    heartbeat = function(time, speed)
        local val = sin(time * (speed or 4.0))
        return (val > 0.0) and (val ^ 4.0) or 0.0
    end,

    wobble = function(time, speed, amplitude)
        return sin(time * (speed or 5.0)) * (amplitude or 3.0)
    end,

    shake = function(time, speed, amplitude)
        local s = sin(time * (speed or 25.0))
        local c = cos(time * (speed or 25.0) * 1.3)
        return s * (amplitude or 2.0), c * (amplitude or 2.0)
    end,

    flash = function(time, speed)
        return (sin(time * (speed or 8.0)) > 0.2) and 1.0 or 0.0
    end,

    swing = function(time, speed, amplitude)
        return sin(time * (speed or 2.5)) * (amplitude or 4.0)
    end
}

return M