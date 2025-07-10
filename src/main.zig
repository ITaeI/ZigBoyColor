const std = @import("std");
const GUI = @import("GUI.zig").GUI;

pub fn main() !void {
    var gui = GUI{};
    try gui.init("ZigBoyColor", 640, 576);
    gui.Run();
}


