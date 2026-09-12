local M = {}

function M.draw()
    ui.begin_row(24)
    if ui.button("|<") then chess.to_start() end
    if ui.button("<")  then chess.undo() end
    if ui.button(">")  then chess.redo() end
    if ui.button(">|") then chess.to_end() end
    ui.end_row()

    ui.label("position", chess.status(), chess.in_check() and "warn" or "dim")
    ui.separator()

    ui.move_list()
end

return M
