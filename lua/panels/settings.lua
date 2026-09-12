local M = {}

local time_controls = {
    { label = "1+0",   kind = "increment", base = 60,  inc = 0 },
    { label = "3+2",   kind = "increment", base = 180, inc = 2 },
    { label = "10+5",  kind = "increment", base = 600, inc = 5 },
    { label = "1s/mv", kind = "movetime",  base = 1000 },
    { label = "d10",   kind = "depth",     base = 10 },
}

function M.draw()
    ui.heading("Match")

    ui.dim("white")
    ui.begin_row(22)
    if ui.button("human") then match.set_player("white", "human") end
    for _, e in ipairs(engine.list()) do
        if ui.button(e.name) then match.set_player("white", e.index) end
    end
    ui.end_row()

    ui.dim("black")
    ui.begin_row(22)
    if ui.button("human") then match.set_player("black", "human") end
    for _, e in ipairs(engine.list()) do
        if ui.button(e.name) then match.set_player("black", e.index) end
    end
    ui.end_row()

    ui.dim("time control")
    ui.begin_row(22)
    for _, tc in ipairs(time_controls) do
        if ui.button(tc.label) then
            match.set_time(tc.kind, tc.base, tc.inc or 0)
            app.set_status("time control: " .. tc.label)
        end
    end
    ui.end_row()

    ui.separator()

    local state = match.state()
    ui.label("state", state, state == "playing" and "good" or "dim")

    if state ~= "idle" then
        local w, l, d = match.score()
        ui.label("score", string.format("%d - %d - %d", w, l, d), "bright")
        ui.clocks()
    end

    ui.begin_row(26)
    if state == "idle" or state == "finished" then
        if ui.button("start match", "primary") then match.start() end
    else
        if ui.button("abort", "danger") then match.abort() end
    end
    if ui.button("new board") then chess.new_game() end
    ui.end_row()

    ui.separator()
    ui.heading("UI")
    ui.dim("scripts: " .. app.script_dir())
    ui.label("api version", tostring(app.api_version), "dim")

    if ui.button("reload ui", "primary") then
        app.reload_ui()
    end
end

return M
