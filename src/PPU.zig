const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const Register = @import("SM83.zig").Register8Bit;


pub const PPU = struct {

    Emu : *GBC,
    vram : VRAM,

    regs : Registers,


    pub fn init (parentPtr : *GBC) PPU{
        return PPU{
            .Emu = parentPtr,
            .vram = VRAM{.Banks = .{.{0}**0x2000}**0x2,.CurrentBank = 0},
            .regs = Registers.init(),
        };
    }

    pub fn tick(self: *PPU) void{
        _ = self;
    }

};

const VRAM = struct {
    Banks : [2][0x2000]u8,
    CurrentBank : u8,

    pub fn read(self: *VRAM, address : u16)u8{
        return self.Banks[self.CurrentBank][address];
    }

    pub fn write(self: *VRAM, address : u16, data: u8)void{
        self.Banks[self.CurrentBank][address] = data;
    }
};

const Registers = struct {
    // PPU Register Set
    lcdc : LCDC = undefined,
    stat : STAT = undefined,
    scy  : Register = undefined,
    scx  : Register = undefined,
    ly   : Register = undefined,
    lyc  : Register = undefined,
    dma  : Register = undefined,
    bgp  : Register = undefined,
    obp0 : Register = undefined,
    obp1 : Register = undefined,
    wy   : Register = undefined,
    wx   : Register = undefined,

    pub fn init() Registers{
        var r = Registers{};

        r.lcdc = @bitCast(@as(u8,0x91));
        r.scy.set(0x00);
        r.scx.set(0x00);
        r.lyc.set(0x00);
        r.dma.set(0x00);
        r.bgp.set(0xFC);
        r.wy.set(0x00);
        r.wx.set(0x00);

        return r;
    }
};

const OAMEntry = packed struct {
    X : u8,
    Y : u8,
    tile : u8,

    CGB_Palette : u3,
    Bank_No : u1,
    Palette : u1,
    XFlip : u1,
    YFlip : u1,
    Priority : u1,
};

const LCDC = packed struct {
    BGWindowPriority : bool,
    OBJenable : bool,
    OBJsize : bool,
    BGtileMap : bool,
    BGWinTileData : bool,
    WindowEnable : bool,
    WindowTileMap : bool,
    LCDPPUEnable : bool,
};

const STAT = packed struct {
    PPUmode : u2,    // read only
    LYCeqlLY : bool, // read only
    Mode0Int : bool,
    Mode1Int : bool,
    Mode2Int : bool,
    LYCInt   : bool,
    empty    : u1,
};

