const std = @import("std");
const GBC = @import("GBC.zig").GBC;

pub fn main() !void {
    var ZigBoyColor = GBC{};
    ZigBoyColor.init();
    try ZigBoyColor.Run(" ");
}


