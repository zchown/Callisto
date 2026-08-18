const std = @import("std");
const rl = @import("raylib");

pub fn main() !void {


    const screen_w: i32 = 1000;
    const screen_h: i32 = 1000;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    rl.initWindow(screen_w, screen_h, "Callipso");
    defer rl.closeWindow();

    while (!rl.windowShouldClose())  {

        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.black);
    }
}
