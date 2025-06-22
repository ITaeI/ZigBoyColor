const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const SM83 = @import("SM83.zig").SM83;
const Cart = @import("Cartridge.zig").Cartridge;
const PPU = @import("PPU.zig").PPU;
const Timer  = @import("Timer.zig").Timer;
const DMA = @import("DMA.zig").DMA;


// Memory Mapped Read and Writes

pub const MemoryMap =struct {

    // We Will have pointers to our GBC components
    Emu   : *GBC,
    cpu   : *SM83,
    cart  : *Cart,
    ppu   : *PPU,
    timer : *Timer,
    dma   : *DMA,

    // This is the workram which has 8 different banks
    wram : WRAM,
    // This is the High Ram
    hram : [0x80]u8,
    // These are the IO Registers
    io   : IO,

    pub fn init(parentPtr : *GBC) MemoryMap{
        return MemoryMap{
            .Emu = parentPtr,
            .cpu = &parentPtr.cpu,
            .cart = &parentPtr.cart,
            .ppu = &parentPtr.ppu,
            .timer = &parentPtr.timer,
            .dma = &parentPtr.dma,

            .wram = WRAM{},
            .hram = [_]u8{0} ** 0x80,
            .io = IO.init(parentPtr),
        };
    }

    pub fn read(self : *MemoryMap, address : u16) u8 {

        return switch (address) {
            0...0x7FFF => self.cart.read(address),
            0x8000...0x9FFF => self.ppu.vram.read(address),
            0xC000...0xDFFF => self.wram.read(address),
            0xFE00...0xFE9F => blk :{
                if(self.dma.OAMTransferInProgress) return 0xFF;
                break :blk self.ppu.oam.read(address);
            }, // DMA
            0xFEA0...0xFEFF => 0xFF, // unusable
            0xFF00...0xFF7F => self.io.read(address), // IO
            0xFF80...0xFFFE => self.hram[address - 0xFF80], // High Ram
            0xFFFF => self.cpu.regs.IE.get(), // IE register
            else => 0xFF,
        };
    }

    pub fn write(self : *MemoryMap, address : u16, data : u8) void {

        switch (address) {
            0...0x7FFF =>self.cart.write(address,data),
            0x8000...0x9FFF =>self.ppu.vram.write(address,data),
            0xA000...0xBFFF =>self.cart.write(address, data),
            0xC000...0xDFFF => self.wram.write(address, data),
            0xFE00...0xFE9F => {
                if(self.dma.OAMTransferInProgress) return;
                self.ppu.oam.write(address-0xFE00, data);
            }, // DMA
            0xFEA0...0xFEFF => {}, // unusable
            0xFF00...0xFF7F => self.io.write(address, data), // IO
            0xFF80...0xFFFE => self.hram[address - 0xFF80] = data, // High Ram
            0xFFFF =>self.cpu.regs.IE.set(data), // IE register
            else => {},
        }
    }
};

const WRAM = struct {
    FixedBank : [0x2000]u8 = .{0} ** 0x2000,
    CGBBanks : [7][0x1000]u8 = .{.{0} ** 0x1000} ** 7,
    CurrentBank : u8 = 1,

    pub fn read(self: *WRAM, address : u16) u8{
        return if(address <= 0xCFFF ) self.FixedBank[address & 0x1FFF] else self.CGBBanks[self.CurrentBank][address&0xFFF];
    }

    pub fn write(self : *WRAM, address : u16, data : u8) void {
        if(address <= 0xCFFF) self.FixedBank[address&0x1FFF] = data else self.CGBBanks[self.CurrentBank][address&0xFFF] = data;
    }
};

const IO = struct {

    Emu   : *GBC,
    cpu   : *SM83,
    cart  : *Cart,
    ppu   : *PPU,
    timer : *Timer,
    dma   : *DMA,

    serialData : [2]u8 = [_]u8{0,0x7F},

    joypad : JoyPad,

    pub fn init(parentPtr : *GBC) IO{

        return IO{
            .Emu = parentPtr,
            .cpu = &parentPtr.cpu,
            .cart = &parentPtr.cart,
            .ppu = &parentPtr.ppu,
            .timer = &parentPtr.timer,
            .joypad = JoyPad.init(),
            .dma = &parentPtr.dma,
        };
    }

    pub fn read(self : *IO, address : u16)u8{

        return switch (address) {
            0xFF00 => self.joypad.read(),
            0xFF01 => self.serialData[0],
            0xFF02 => self.serialData[1],
            0xFF04...0xFF07 =>self.timer.read(address), 
            0xFF0F =>self.cpu.regs.IF.get(), 
            0xFF10...0xFF26 => 0xFF, // APU
            0xFF30...0xFF3F => 0xFF, // WaveRAM
            0xFF40...0xFF4B => self.ppu.read(address),
            0xFF4F => 0xFE | (self.ppu.vram.CurrentBank&1),
            0xFF50 => 0xFF, // Bootrom Disable?
            0xFF55 => self.dma.read(),
            0xFF68...0xFF6B => 0xFF, // CGB Color Palettes
            0xFF70 => self.Emu.bus.wram.CurrentBank, 
            else => 0xFF,
        };
    }

    pub fn write(self : *IO, address : u16,data : u8)void{
            switch (address) {
            0xFF00 => self.joypad.write(data),
            0xFF01 => self.serialData[0] = data,
            0xFF02 => self.serialData[1] = data,
            0xFF04...0xFF07 => self.timer.write(address, data), //timer
            0xFF0F =>self.cpu.regs.IF.set(data), // IF reg from cpu
            0xFF10...0xFF26 => {}, // APU
            0xFF30...0xFF3F => {}, // WaveRAM
            0xFF40...0xFF4B => self.ppu.write(address, data),
            0xFF4C => {}, // cpu mode select - set at the beginning
            0xFF4D => {}, // Key 1
            0xFF4F => self.ppu.vram.CurrentBank = data&1,
            0xFF50 => {}, // Bootrom Disable?
            0xFF51...0xFF55 => self.dma.write(address, data),
            0xFF68...0xFF6B => {}, // CGB Color Palettes
            0xFF6C => {}, // object priority mode - set at the beginning
            0xFF70 => self.Emu.bus.wram.CurrentBank = if(data & 7 == 0 ) 1 else data & 7, 
            else => {},
        }
    }
};

const JoyPad = struct {
    var state : u8 = 0xFF;

    var selectDpad : bool = false;
    var selectButtons : bool = false;

    pub fn init() JoyPad{
        return JoyPad{};
    }

    pub fn read(self : *JoyPad) u8{
        if(selectDpad){
            return @as(u8,(1<<4)) | (state&0xF);
        }
        else if(selectButtons){
            return @as(u8,(2<<4)) | (state>>4);
        }
        
        _ = self;
        return 0xCF;
    }

    pub fn write(self : *JoyPad, data : u8)void{

        if((data >> 4 & 0x1) == 0x00) // Check if dpad was selected
        {
            selectDpad = true;
            selectButtons = false;
            
        }
        else if((data >> 5 & 0x1) == 0x00) // Check if buttons were selected
        {
            selectButtons = true;
            selectDpad = false;
        }

        _ = self;
    }

    pub fn pressKey(self : JoyPad,comptime bit : u8)void{
        state &= ~(@as(u8,(1)) << bit);

        if(bit <= 3 and selectDpad){
            // set IF joypad interrupt IF Bit
        }
        else if(bit >= 4 and selectButtons){
            //also set joypad interrupt IF bit
        }

        _ = self;
    }

    pub fn releaseKey(self : JoyPad, comptime bit : u8)void{
        state |= (@as(u8,(1)) << bit);
        _ = self;
    }
};
