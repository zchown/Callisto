local M = {}

local function playing()
    local state = match.state()
    return state == "playing" or state == "between"
end

local function seat_card(side)
    local seat = match.seat(side)

    if seat.kind == "engine" then
        ui.engine_card({
            engine = seat.engine,
            side   = side,
            lines  = 1,
            board  = true,
            clock  = true,
        })
    else
        ui.engine_card({ side = side, name = seat.name, clock = true })
    end
end

function M.draw()
    if playing() then
        seat_card("black")
        ui.spacing(8)
        seat_card("white")
        return
    end

    if engine.count() == 0 then
        ui.dim("no engines configured")
        return
    end

    local any = false
    for _, e in ipairs(engine.list()) do
        if e.analysing then
            any = true
            ui.engine_card({ engine = e.index, lines = 4, board = true })
            ui.spacing(8)
        end
    end

    if not any then
        ui.dim("no engine is analysing")
        ui.spacing(4)
        if ui.button("start analysis", "primary") then
            engine.set_analysis(true)
        end
    end
end

return M
