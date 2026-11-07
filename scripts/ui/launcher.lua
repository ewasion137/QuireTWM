local launcher = {}

Quire.launcher_active = false
Quire.launcher_index = 1

local query = ""
local filtered_apps = {}
local anim_y = 0.0
local anim_alpha = 0.0

local default_catalog = {{
    name = "Terminal",
    path = "wt.exe",
    badge = "APP"
}, {
    name = "Command Prompt",
    path = "cmd.exe",
    badge = "CMD"
}, {
    name = "File Explorer",
    path = "explorer.exe",
    badge = "APP"
}, {
    name = "Task Manager",
    path = "taskmgr.exe",
    badge = "SYS"
}, {
    name = "Notepad",
    path = "notepad.exe",
    badge = "APP"
}, {
    name = "Calculator",
    path = "calc.exe",
    badge = "APP"
}, {
    name = "Settings",
    path = "ms-settings:",
    badge = "SYS"
}, {
    name = "Control Panel",
    path = "control.exe",
    badge = "SYS"
}, {
    name = "Registry Editor",
    path = "regedit.exe",
    badge = "SYS"
}}

local function get_catalog()
    if Quire.apps and #Quire.apps > 0 then
        return Quire.apps
    end
    return default_catalog
end

function launcher.filter()
    filtered_apps = {}
    local catalog = get_catalog()
    local q = query:lower():gsub("^%s+", ""):gsub("%s+$", "")

    if q == "" then
        for _, app in ipairs(catalog) do
            table.insert(filtered_apps, {
                name = app.name,
                path = app.path,
                badge = app.badge or "APP"
            })
        end
    else
        for _, app in ipairs(catalog) do
            local name_low = app.name:lower()
            local path_low = app.path:lower()
            if name_low:find(q, 1, true) or path_low:find(q, 1, true) then
                table.insert(filtered_apps, {
                    name = app.name,
                    path = app.path,
                    badge = app.badge or "APP"
                })
            end
        end

        table.insert(filtered_apps, {
            name = "Run: " .. query,
            path = query,
            badge = "CMD",
            is_custom = true
        })
    end

    if Quire.launcher_index > #filtered_apps then
        Quire.launcher_index = math.max(1, #filtered_apps)
    end
end

function launcher.toggle()
    Quire.launcher_active = not Quire.launcher_active
    if Quire.launcher_active then
        query = ""
        Quire.launcher_index = 1
        anim_y = 0.0
        anim_alpha = 0.0
        launcher.filter()
        if wm.set_input_capture then
            wm.set_input_capture(true)
        end
    else
        launcher.close()
    end
end

function launcher.close()
    Quire.launcher_active = false
    if wm.set_input_capture then
        wm.set_input_capture(false)
    end
end

function launcher.navigate(dir)
    if not Quire.launcher_active then
        return
    end
    local count = #filtered_apps
    if count == 0 then
        return
    end
    if dir == "down" then
        Quire.launcher_index = (Quire.launcher_index % count) + 1
    elseif dir == "up" then
        Quire.launcher_index = (Quire.launcher_index - 2 + count) % count + 1
    end
end

function launcher.commit()
    if not Quire.launcher_active then
        return
    end
    local app = filtered_apps[Quire.launcher_index]
    if app and app.path ~= "" then
        wm.spawn(app.path)
    end
    launcher.close()
end

function launcher.on_key(vk, char)
    if not Quire.launcher_active then
        return false
    end

    if vk == 0x1B then
        launcher.close()
        return true
    end

    if vk == 0x0D then
        launcher.commit()
        return true
    end

    if vk == 0x26 then
        launcher.navigate("up")
        return true
    end

    if vk == 0x28 then
        launcher.navigate("down")
        return true
    end

    if vk == 0x09 then
        launcher.navigate("down")
        return true
    end

    if vk == 0x08 then
        if #query > 0 then
            local len = utf8.len(query)
            if len and len > 0 then
                local offset = utf8.offset(query, len)
                if offset then
                    query = query:sub(1, offset - 1)
                else
                    query = query:sub(1, -2)
                end
            else
                query = ""
            end
            launcher.filter()
        end
        return true
    end

    if char and #char > 0 then
        local b = char:byte(1)
        if b >= 32 then
            query = query .. char
            launcher.filter()
            return true
        end
    end

    return false
end

function launcher.draw(alpha_mult)
    if not Quire.launcher_active and anim_alpha < 0.01 then
        return
    end

    local target_alpha = Quire.launcher_active and 1.0 or 0.0
    anim_alpha = anim_alpha + (target_alpha - anim_alpha) * 0.30

    if anim_alpha < 0.01 then
        return
    end

    local sw, sh = wm.get_screen_size()
    local t = Quire.theme
    local accent = Quire.config.border_active or t.active_border_color

    local panel_w = 540
    local item_h = 42
    local gap_y = 4
    local max_visible = 6

    local count = #filtered_apps
    local display_count = math.min(count, max_visible)
    local list_h = display_count > 0 and (display_count * (item_h + gap_y)) or 50
    local panel_h = 60 + list_h + 34

    local px = math.floor((sw - panel_w) / 2)
    local py = math.floor((sh - panel_h) / 2)

    if ui.draw_shadow_rounded_rect then
        ui.draw_shadow_rounded_rect(px, py, panel_w, panel_h, t.rounding + 2, 0.0, 0.0, 0.0, 0.55 * anim_alpha, 16.0,
            3.0)
    end

    ui.fill_rounded_rect(px, py, panel_w, panel_h, t.rounding, 0.06, 0.07, 0.09, 0.96 * anim_alpha)
    ui.draw_rounded_rect(px, py, panel_w, panel_h, t.rounding, t.border_color[1], t.border_color[2], t.border_color[3],
        0.35 * anim_alpha, 1.0)

    local search_y = py + 14
    ui.draw_text(">", px + 18, search_y + 4, 13, accent[1], accent[2], accent[3], anim_alpha, t.font_family)

    local input_str = query
    if input_str == "" then
        ui.draw_text("Search apps or run command...", px + 36, search_y + 4, 12, 0.45, 0.48, 0.55, 0.70 * anim_alpha,
            t.font_family)
    else
        ui.draw_text(input_str, px + 36, search_y + 4, 12, 0.95, 0.95, 0.98, anim_alpha, t.font_family)
    end

    local text_w = ui.measure_text(input_str, 12, t.font_family)
    local cursor_x = px + 36 + text_w + 2
    local now = wm.get_time and wm.get_time() or os.clock()
    if (math.floor(now * 2.2) % 2) == 0 then
        ui.fill_rect(cursor_x, search_y + 4, 2, 16, accent[1], accent[2], accent[3], anim_alpha)
    end

    local sep_y = py + 52
    ui.draw_line(px + 12, sep_y, px + panel_w - 12, sep_y, t.border_color[1], t.border_color[2], t.border_color[3],
        0.25 * anim_alpha, 1.0)

    local offset = 0
    if count > max_visible then
        offset = math.max(0, math.min(count - max_visible, Quire.launcher_index - math.floor(max_visible / 2) - 1))
    end

    local target_pill_y = 0.0
    for i = 1, display_count do
        local idx = i + offset
        if idx == Quire.launcher_index then
            target_pill_y = sep_y + 8 + (i - 1) * (item_h + gap_y)
            break
        end
    end

    if target_pill_y > 0.0 then
        if anim_y == 0.0 then
            anim_y = target_pill_y
        else
            anim_y = anim_y + (target_pill_y - anim_y) * 0.35
        end

        ui.fill_rounded_rect(px + 10, anim_y, panel_w - 20, item_h, 6, accent[1], accent[2], accent[3],
            0.16 * anim_alpha)
        ui.draw_rounded_rect(px + 10, anim_y, panel_w - 20, item_h, 6, accent[1], accent[2], accent[3],
            0.40 * anim_alpha, 1.0)
    end

    if display_count == 0 then
        ui.draw_text("No matching applications", px + 22, sep_y + 16, 11, 0.50, 0.52, 0.60, anim_alpha, t.font_family)
    else
        for i = 1, display_count do
            local idx = i + offset
            local app = filtered_apps[idx]
            if app then
                local iy = sep_y + 8 + (i - 1) * (item_h + gap_y)
                local is_sel = (idx == Quire.launcher_index)

                local name_color = is_sel and {0.98, 0.98, 1.0, 1.0} or {0.75, 0.78, 0.84, 0.85}
                ui.draw_text(app.name, px + 22, iy + 12, 11, name_color[1], name_color[2], name_color[3],
                    name_color[4] * anim_alpha, t.font_family)

                local badge_text = app.badge or "APP"
                local bw = ui.measure_text(badge_text, 9, t.font_family) + 12
                local bx = px + panel_w - bw - 20
                ui.fill_rounded_rect(bx, iy + 11, bw, 18, 4, 0.12, 0.14, 0.18, 0.85 * anim_alpha)
                ui.draw_text(badge_text, bx + 6, iy + 14, 9, 0.65, 0.70, 0.82, 0.90 * anim_alpha, t.font_family)
            end
        end
    end

    local foot_y = py + panel_h - 26
    ui.draw_line(px + 12, foot_y - 6, px + panel_w - 12, foot_y - 6, t.border_color[1], t.border_color[2],
        t.border_color[3], 0.20 * anim_alpha, 1.0)
    ui.draw_text("Enter to run   Esc to dismiss   Up/Down to navigate", px + 18, foot_y, 9, 0.45, 0.48, 0.55,
        0.70 * anim_alpha, t.font_family)
end

return launcher
