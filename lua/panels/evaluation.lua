local M = {}

local function format_nodes(n)
    if n >= 1000000 then
        return string.format("%.1fM", math.floor(n / 1000000))
    elseif n >= 1000 then
        return string.format("%dk", math.floor(n / 1000))
    end
    return tostring(n)
end

function M.draw()
    ui.eval_bar(14)
    ui.spacing(6)

    if engine.count() == 0 then
        ui.dim("no engines configured")
        ui.spacing(4)
        if ui.button("open settings", "primary") then
            app.set_view("analysis")
        end
        return
    end

    local score, kind = engine.score()
    if score == nil then
        ui.label("score", "--", "dim")
    elseif kind == "mate" then
        ui.label("score", "mate in " .. math.abs(score), score > 0 and "good" or "bad")
    else
        ui.label("score", engine.score_text(), score > 0 and "good" or (score < 0 and "bad" or "dim"))
    end

    ui.label("depth", tostring(engine.depth()), "normal")
    ui.label("nodes", format_nodes(engine.nodes()), "dim")
    ui.label("speed", format_nodes(engine.nps()) .. "/s", "dim")

    ui.separator()

    ui.begin_row(24)
    if ui.button(engine.analysing() and "stop" or "analyse", engine.analysing() and "danger" or "primary") then
        engine.set_analysis(not engine.analysing())
    end
    if ui.button("2 lines") then engine.set_multipv(2) end
    if ui.button("4 lines") then engine.set_multipv(4) end
    ui.end_row()

    ui.spacing(4)
    ui.engine_lines(4)
end

return M
