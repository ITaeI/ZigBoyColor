const std = @import("std");
const GUI = @import("GUI.zig").GUI;

pub fn main() !void {
    var gui = try GUI.init("ZigBoyColor", 640, 576);
    try gui.Run();
    gui.deinit();
}


