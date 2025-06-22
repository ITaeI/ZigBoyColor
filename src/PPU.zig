const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const Register = @import("SM83.zig").Register8Bit;


pub const PPU = struct {

    Emu : *GBC,
    vram : VRAM,
    oam : OAM,

    regs : Registers,

    var dots: u32 = 0;
    var mode: PPUmodes = PPUmodes.OAMScan; 

    var sprites : [10]usize = undefined;
    var spriteCount : usize = 0;

    const DotsPerFrame:u32 = 70224;


    pub fn init (parentPtr : *GBC) PPU{
        return PPU{
            .Emu = parentPtr,
            .vram = VRAM{},
            .oam = OAM{},
            .regs = Registers.init(),
        };
    }

    pub fn tick(self: *PPU) void{

        dots +%= 1;

        if(!self.regs.lcdc.LCDPPUEnable){
            if(dots >= DotsPerFrame){
                dots -= DotsPerFrame;
            }
        }

        switch (mode) {
            .OAMScan => {

                if(dots >= 80)
                {
                    self.scanOAM(); // scans the oam 
                    dots -= 80;
                    mode = PPUmodes.DrawingPixels;
                    self.regs.stat.PPUmode = mode;
                }
            },
            .DrawingPixels => {

                if(dots >= 12 and dots < 172){
                    //here we draw the pixels
                }
                else if(dots >= 172){
                    dots -= 172;
                    mode = PPUmodes.HBlank;
                    self.regs.stat.PPUmode = mode;

                    if(self.regs.stat.Mode0Int){
                        self.Emu.cpu.regs.IF.setBit(1, 1);
                    }
                }

            },
            .HBlank => {    
            
                if(dots >= 204)
                {
                    // DMA
                    self.Emu.dma.Hblank();

                    dots -= 204;
                    mode = PPUmodes.OAMScan;

                    self.regs.ly.Inc();
                    self.compareLY_LYC();

                    if(self.regs.ly.get() == 144){
                        mode = PPUmodes.VBlank;
                        self.regs.stat.PPUmode = mode;

                        // Request Interrupts accordingly
                        self.Emu.cpu.regs.IF.setBit(0, 1);

                        if(self.regs.stat.Mode1Int){
                        self.Emu.cpu.regs.IF.setBit(1, 1);
                        }
                    }
                    else{
                        self.regs.stat.PPUmode = mode;

                        if(self.regs.stat.Mode2Int){
                            self.Emu.cpu.regs.IF.setBit(1, 1);
                        }
                    }
                }
                
            },
            .VBlank => {

                if(dots >= 456){
                    dots -= 456;
                    self.regs.ly.Inc();

                    if(self.regs.ly.get() == 154){

                        self.regs.ly.set(0);
                        self.compareLY_LYC();

                        mode = PPUmodes.OAMScan;
                        self.regs.stat.PPUmode = mode;

                        if(self.regs.stat.Mode2Int){
                            self.Emu.cpu.regs.IF.setBit(1, 1);
                        }

                    }
                }
            },
        }
    }

    pub fn read(self : *PPU, address: u16) u8{

        return switch (address) {
            0xFF40 => @bitCast(self.regs.lcdc),
            0xFF41 => @bitCast(self.regs.stat),
            0xFF42 => self.regs.scy.get(),
            0xFF43 => self.regs.scx.get(),
            0xFF44 => self.regs.ly.get(),
            0xFF45 => self.regs.lyc.get(),
            0xFF46 => self.regs.dma.get(),
            0xFF47 => self.regs.bgp.get(),
            0xFF48 => self.regs.obp0.get(),
            0xFF49 => self.regs.obp1.get(),
            0xFF4A => self.regs.wy.get(),
            0xFF4B => self.regs.wx.get(),
            else => 0xFF,

        };

    }

    pub fn write(self : *PPU, address: u16,data: u8)void{
        return switch (address) {
            0xFF40 => self.regs.lcdc = @bitCast(data),
            0xFF41 => self.regs.stat = @bitCast((@as(u8,@bitCast(self.regs.stat)) & 3) | (data & 0xFC)),
            0xFF42 => self.regs.scy.set(data),
            0xFF43 => self.regs.scx.set(data),
            0xFF44 => self.regs.ly.set(data),
            0xFF45 => self.regs.lyc.set(data),
            0xFF46 => {
                if(self.Emu.dma.OAMTransferInProgress) return;

                self.regs.dma.set(data);
                self.Emu.dma.StartOAMTransfer(data);
            },
            0xFF47 => self.regs.bgp.set(data),
            0xFF48 => self.regs.obp0.set(data),
            0xFF49 => self.regs.obp1.set(data),
            0xFF4A => self.regs.wy.set(data),
            0xFF4B => self.regs.wx.set(data),
            else => {},

        };
    }

    fn scanOAM(self : *PPU) void {

        const ly : u8 = self.regs.ly.get();
        const ObjHeight: u8 = if(self.regs.lcdc.OBJsize) 16 else 8;

        // clear past sprites
        for(0..spriteCount)|i|{
            sprites[i] = 0;
        }
        spriteCount = 0;

        // grab the indexes for visible sprites
        for(self.oam.Entries,0..) |entry,i|{
            
            if(entry.X != 0 and ly + 16 >= entry.Y and ly + 16 <= entry.Y + ObjHeight - 1){
                sprites[spriteCount] = i;
                spriteCount += 1;
            }
            // 10 sprites maximum
            if(spriteCount == 10){
                return;
            }
        }
    }

    fn compareLY_LYC (self: *PPU) void{

        self.regs.stat.LYCeqlLY = self.regs.ly.get() == self.regs.lyc.get();
        if(self.regs.stat.LYCeqlLY){
            // set LCD interrupt to true in the cpu
            self.Emu.cpu.regs.IF.setBit(1, 1);
        }
    }

};

pub const VRAM = struct {
    Banks : [2][0x2000]u8 = .{.{0}**0x2000}**0x2,
    CurrentBank : u8 = 0,

    pub fn read(self: *VRAM, address : u16)u8{
        return self.Banks[self.CurrentBank][address - 0x8000];
    }

    pub fn write(self: *VRAM, address : u16, data: u8)void{
        self.Banks[self.CurrentBank][address - 0x8000] = data;
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

pub const OAM = struct {

    Entries : [40]OAMEntry = undefined,

    pub fn write(self:*OAM, Index : u16, data: u8)void{
        const EntryIndex = Index / 4;
        const BitOffset:u5 = @truncate(Index % 4);

        const masked : u32 = @as(u32,@bitCast(self.Entries[EntryIndex])) & ~(@as(u32,0xFF) << (BitOffset*8));
        const Edited : u32 = masked | (@as(u32,data) << (BitOffset*8));

        self.Entries[EntryIndex] = @bitCast(Edited);
    }

    pub fn read(self : *OAM, address : u16) u8{
        const EntryIndex = (address-0xFE00) / 4;
        const bitOffset:u5 = @truncate((address-0xFE00) % 4);

        const raw:u32 = @bitCast(self.Entries[EntryIndex]);

        return @truncate(raw >> (bitOffset*8));
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
    PPUmode : PPUmodes,    // read only
    LYCeqlLY : bool, // read only
    Mode0Int : bool,
    Mode1Int : bool,
    Mode2Int : bool,
    LYCInt   : bool,
    empty    : u1,
};

const PPUmodes = enum(u2) {
    HBlank, // mode 0
    VBlank, // mode 1
    OAMScan, // mode 2
    DrawingPixels, // mode 3
};

