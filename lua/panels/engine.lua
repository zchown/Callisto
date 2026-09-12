local M = {}

function M.draw()
    ui.heading("Engines")

    ui.begin_row(26)
    ui.width(ui.available_width() - 70)
    local path, submitted = ui.input("engine_path", "", "path to a UCI engine binary")
    if ui.button("add", "primary") or submitted then
        if #path > 0 then
            engine.add(path)
        end
    end
    ui.end_row()

    ui.dim("or drop a binary onto the window")
    ui.separator()

    local list = engine.list()
    if #list == 0 then
        ui.dim("nothing configured yet")
        return
    end

    for _, e in ipairs(list) do
        ui.begin_row(22)
        ui.width(ui.available_width() - 200)
        ui.text(e.name)
        ui.badge(e.status, e.status == "ready" and "good" or (e.status == "failed" and "bad" or "dim"))
        ui.end_row()

        ui.begin_row(22)
        if ui.button(e.analysing and "analysing" or "analyse", e.analysing and "primary" or "normal") then
            engine.set_analysis(not e.analysing)
        end
        if ui.button("restart") then engine.restart(e.index) end
        if ui.button("remove", "danger") then engine.remove(e.index) end
        ui.end_row()

        ui.separator()
    end
end

return M
