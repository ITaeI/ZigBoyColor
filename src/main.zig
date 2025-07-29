const std = @import("std");
const GUI2 = @import("GUI.zig").GUI2;

pub fn main() !void {
    var gui = GUI2{};
    try gui.init("ZigBoyColor", 1150, 640);
    try gui.Run();
}


