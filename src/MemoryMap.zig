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
            0x8000...0x9FFF => blk:{
                if(self.ppu.mode == .DrawingPixels) break :blk 0xFF;
                break :blk self.ppu.vram.read(address);
            },
            0xA000...0xBFFF => self.cart.read(address),
            0xC000...0xDFFF => self.wram.read(address),
            // Echo RAM 0xE000 - 0xFDFF
            0xFE00...0xFE9F => blk :{
                if(self.dma.OAMTransferInProgress or self.ppu.mode == .OAMScan or self.ppu.mode == .DrawingPixels) break :blk 0xFF;
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
            0x8000...0x9FFF =>{
                if(self.ppu.mode == .DrawingPixels) return;
                self.ppu.vram.write(address,data);
            },
            0xA000...0xBFFF =>self.cart.write(address, data),
            0xC000...0xDFFF => self.wram.write(address, data),
            // Echo RAM 0xE000 - 0xFDFF
            0xFE00...0xFE9F => {
                if(self.dma.OAMTransferInProgress or self.ppu.mode == .OAMScan or self.ppu.mode == .DrawingPixels) return;
                self.ppu.oam.write(address-0xFE00, data);
            }, // DMA
            0xFEA0...0xFEFF => return, // unusable
            0xFF00...0xFF7F => self.io.write(address, data), // IO
            0xFF80...0xFFFE => self.hram[address - 0xFF80] = data, // High Ram
            0xFFFF =>self.cpu.regs.IE.set(data), // IE register
            else => return,
        }
    }
};

const WRAM = struct {
    FixedBank : [0x1000]u8 = .{0} ** 0x1000,
    CGBBanks : [8][0x1000]u8 = .{.{0} ** 0x1000} ** 8,
    CurrentBank : u8 = 1,

    pub fn read(self: *WRAM, address : u16) u8{
        return if(address <= 0xCFFF ) self.FixedBank[address & 0x0FFF] else self.CGBBanks[self.CurrentBank][address&0xFFF];
    }

    pub fn write(self : *WRAM, address : u16, data : u8) void {
        if(address <= 0xCFFF) self.FixedBank[address&0x0FFF] = data else self.CGBBanks[self.CurrentBank][address&0xFFF] = data;
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
            .joypad = JoyPad.init(parentPtr),
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
            0xFF4D => @bitCast(self.Emu.DoubleSpeed),
            0xFF4F => 0xFE | (self.ppu.vram.CurrentBank&1),
            0xFF50 => 0xFF, // Bootrom Disable?
            0xFF55 => self.dma.read(),
            0xFF68...0xFF6B => self.ppu.read(address), // CGB Color Palettes
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
            0xFF10...0xFF26 => return, // APU
            0xFF30...0xFF3F => return, // WaveRAM
            0xFF40...0xFF4B => self.ppu.write(address, data),
            0xFF4D => self.Emu.DoubleSpeed.Armed = (data & 1) == 1,
            0xFF4F => self.ppu.vram.CurrentBank = data&1,
            0xFF50 => return, // Bootrom Disable?
            0xFF51...0xFF55 => self.dma.write(address, data),
            0xFF68...0xFF6B => self.ppu.write(address, data), // CGB Color Palettes
            0xFF6C => return, // object priority mode - set at the beginning
            0xFF70 => self.Emu.bus.wram.CurrentBank = if(data & 7 == 0 ) 1 else (data & 7 ), 
            else => return,
        }
    }
};

const JoyPad = struct {
    // IF Access

    cpu: *SM83,

    state : u8 = 0xFF,

    selectDpad : bool = false,
    selectButtons : bool = false,

    pub fn init(parentPtr : *GBC) JoyPad{
        return JoyPad{
            .cpu = &parentPtr.cpu,
        };
    }

    pub fn read(self : *JoyPad) u8{
        if(self.selectDpad){
            return @as(u8,(1<<4)) | (self.state&0xF);
        }
        else if(self.selectButtons){
            return @as(u8,(2<<4)) | (self.state>>4);
        }
        
        return 0xCF;
    }

    pub fn write(self : *JoyPad, data : u8)void{

        if((data >> 4 & 0x1) == 0x00) // Check if dpad was selected
        {
            self.selectDpad = true;
            self.selectButtons = false;
            
        }
        else if((data >> 5 & 0x1) == 0x00) // Check if buttons were selected
        {
            self.selectButtons = true;
            self.selectDpad = false;
        }

    }

    pub fn pressKey(self : *JoyPad,comptime bit : u3)void{
        self.state &= ~(@as(u8,(1)) << bit);

        if(bit <= 3 and self.selectDpad){
            self.cpu.regs.IF.setBit(4, 1);
        }
        else if(bit >= 4 and self.selectButtons){
            self.cpu.regs.IF.setBit(4, 1);
        }

    }

    pub fn releaseKey(self : *JoyPad, bit : u3)void{
        self.state |= (@as(u8,(1)) << bit);
    }
};
