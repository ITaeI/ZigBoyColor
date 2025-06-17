const std = @import("std");
const GBC = @import("GBC.zig").GBC;


// Memory Mapped Read and Writes

pub const MemoryMap =struct {

    // We will have a pointer to our parent which owns our components
    Emu : *GBC,
    // This is the workram which has 8 different banks
    wram : WRAM,
    // This is the High Ram
    hram : [0x80]u8,

    pub fn init(parentPtr : *GBC) MemoryMap{
        return MemoryMap{
            .Emu = parentPtr,
            .wram = WRAM{.Banks = .{.{0} ** 0x1000} ** 8, .CurrentBank = 1},
            .hram = [_]u8{0} ** 0x80,
        };
    }

    pub fn read(self : *MemoryMap, address : u16) u8 {
        const Cart = &self.Emu.cart;
        const PPU = &self.Emu.ppu;

        switch (address) {
            0...0x7FFF => return Cart.read(address),
            0x8000...0x9FFF => return PPU.vram.read(address)
        }
    }

    pub fn write(self : *MemoryMap, address : u16, data : u8) void {
        const Cart = &self.Emu.cart;
        const PPU = &self.Emu.ppu;

        switch (address) {
            0...0x7FFF => Cart.write(address,data),
            0x8000...0x9FFF => PPU.vram.write(address,data),
            0xA000...0xBFFF => Cart.write(address, data),
            0xC000...0xDFFF => self.wram.write(address, data),
            0xFE00...0xFE9F => {}, // DMA
            0xFEA0...0xFEFF => {}, // unusable
            0xFF00...0xFF7F => {}, // IO
            0xFF80...0xFFFE => {}, // High Ram
            0xFFFF => {}, // IE register
            else => {},
        }
    }
};

const WRAM = struct {
    Banks : [8][0x1000]u8,
    CurrentBank : u8,

    pub fn read(self: *WRAM, address : u16) u8{
        return self.Banks[self.CurrentBank][address];
    }

    pub fn write(self : *WRAM, address : u16, data : u8) void {
        self.Banks[self.CurrentBank][address] = data;
    }
};
