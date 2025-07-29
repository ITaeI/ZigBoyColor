const std = @import("std");
const GUI = @import("GUI.zig").GUI;

pub fn main() !void {
    var gui = GUI{};
    try gui.init("ZigBoyColor", 1150, 640);
    try gui.Run();
}


