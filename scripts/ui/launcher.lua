local launcher = {}

Quire.launcher_active = false
Quire.launcher_index = 1

Quire.apps = Quire.apps or {
    { name = "Terminal", path = "cmd.exe" },
    { name = "Explorer", path = "explorer.exe" },
    { name = "Task Manager", path = "taskmgr.exe" }
}

function launcher.toggle()
    Quire.launcher_active = not Quire.launcher_active
    Quire.launcher_index = 1
end

function launcher.navigate(dir)
    if not Quire.launcher_active then return end
    local count = #Quire.apps
    if count == 0 then return end
    if dir == "down" then
        Quire.launcher_index = (Quire.launcher_index % count) + 1
    elseif dir == "up" then
        Quire.launcher_index = (Quire.launcher_index - 2 + count) % count + 1
    end
end

function launcher.commit()
    if not Quire.launcher_active then return end
    local app = Quire.apps[Quire.launcher_index]
    if app then wm.spawn(app.path) end
    Quire.launcher_active = false
end

function launcher.draw(alpha)
    if not Quire.launcher_active or (alpha and alpha < 0.01) then return end

    local sw, sh = wm.get_screen_size()
    local t = Quire.theme
    local apps = Quire.apps

    local item_h = 36
    local panel_w = 380
    local panel_h = 50 + (#apps * (item_h + 4))
    local px, py = math.floor((sw - panel_w) / 2), math.floor((sh - panel_h) / 2)

    ui.fill_rounded_rect(px, py, panel_w, panel_h, t.rounding, t.bg_color[1], t.bg_color[2], t.bg_color[3], t.bg_color[4] * (alpha or 1.0))
    ui.draw_rounded_rect(px, py, panel_w, panel_h, t.rounding, t.active_border_color[1], t.active_border_color[2], t.active_border_color[3], 0.4 * (alpha or 1.0), 1)

    for i, app in ipairs(apps) do
        local iy = py + 38 + (i - 1) * (item_h + 4)
        local is_sel = (i == Quire.launcher_index)

        if is_sel then
            ui.fill_rounded_rect(px + 8, iy, panel_w - 16, item_h, 4, t.accent_color[1], t.accent_color[2], t.accent_color[3], 0.25 * (alpha or 1.0))
            ui.draw_text(app.name, px + 18, iy + 10, 12, 1, 1, 1, alpha or 1.0, t.font_family)
        else
            ui.draw_text(app.name, px + 18, iy + 10, 12, t.text_dim[1], t.text_dim[2], t.text_dim[3], alpha or 1.0, t.font_family)
        end
    end
end

return launcher