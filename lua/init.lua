local function load_panel(module)
    local ok, mod = pcall(require, module)
    if not ok then
        app.log("could not load " .. module .. ": " .. tostring(mod), "error")
        return nil
    end
    if type(mod) ~= "table" or type(mod.draw) ~= "function" then
        app.log(module .. " must return a table with a draw function", "error")
        return nil
    end
    return mod
end

local panels = {
    { id = "evaluation",  title = "Evaluation",  module = "panels.evaluation" },
    { id = "engine_info", title = "Engines",     module = "panels.engine" },
    { id = "move_list",   title = "Moves",       module = "panels.moves" },
    { id = "settings",    title = "Settings",    module = "panels.settings" },
}

for _, entry in ipairs(panels) do
    local mod = load_panel(entry.module)
    if mod then
        ui.register_panel(entry.id, entry.title, mod.draw)
    end
end

ui.set_view("home", { panel = "home" })

ui.set_view("game", {
    split = "horizontal",
    ratio = 0.62,
    min_first = 280,
    first = { panel = "board" },
    second = {
        split = "vertical",
        ratio = 0.55,
        first  = { tabs = { "move_list", "match" } },
        second = { tabs = { "engine_info", "log" } },
    },
})

ui.set_view("analysis", {
    split = "horizontal",
    ratio = 0.58,
    min_first = 280,
    first = { panel = "board" },
    second = {
        split = "vertical",
        ratio = 0.58,
        first  = { tabs = { "evaluation", "engine_info" } },
        second = { tabs = { "move_list", "settings", "log" } },
    },
})

app.map("a", function()
    engine.set_analysis(not engine.analysing())
end)

app.map("n", function()
    chess.new_game()
    app.set_status("new game")
end)

app.map("c", function()
    app.clipboard(chess.fen())
    app.set_status("FEN copied")
end)

app.log("UI loaded from " .. app.script_dir())
