const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const MMap = @import("MemoryMap.zig").MemoryMap;
const VRAM = @import("PPU.zig").VRAM;
const OAM = @import("PPU.zig").OAM;


pub const DMA = struct {

    Emu : *GBC,
    vram : *VRAM,
    oam  : *OAM,

    OAMTransferInProgress: bool = false,
    VRAMTransferInProgress: bool = false,

    oamStartAddress: u16 = undefined,
    oamCurrentIndex: u16 = undefined,

    HDMA12 : u16 = 0xFFFF,
    HDMA34 : u16 = 0xFFFF,
    HDMA5 : VRAM_DMA_Control = @bitCast(@as(u8,0xFF)),


    pub fn init(parentPtr : *GBC) DMA{

        return DMA{
            .Emu  = parentPtr,
            .vram = &parentPtr.ppu.vram,
            .oam = &parentPtr.ppu.oam,
        };
    }

    pub fn write(self : *DMA, address: u16, data : u8)void{

        if(!self.Emu.CGBMode) return;
        switch (address) {
            0xFF51 => self.HDMA12 = (self.HDMA12&0x00FF) | (@as(u16,data) << 8),
            0xFF52 => self.HDMA12 = (self.HDMA12&0xFF00) | @as(u16,data&0xF0),
            0xFF53 => self.HDMA34 = (self.HDMA34&0x00FF) | (@as(u16,data&0x1F) << 8),
            0xFF54 => self.HDMA34 = (self.HDMA34&0xFF00) | @as(u16,data&0xF0),
            0xFF55 => self.startVRAMTransfer(data),
            else => {},        
        }

    }

    pub fn read(self : *DMA)u8{
        if(!self.Emu.CGBMode) return 0xFF;
        const active : u8 = @as(u8,@intFromBool(self.VRAMTransferInProgress)) << 7;
        return ((~active) & 0x80) | @as(u8,self.HDMA5.TransferLength);
    }

    fn startVRAMTransfer(self: *DMA,data:u8)void{

        const PrevMode = self.HDMA5.TransferMode;
        const PrevActivity = self.VRAMTransferInProgress;
        self.VRAMTransferInProgress = true;
        self.HDMA5 = @bitCast(data);

        // you can cancel a active hblank dma by writing 0 to bit 7
        if((PrevMode == .Hblank and PrevActivity) and self.HDMA5.TransferMode == .GeneralPurpose){
            self.VRAMTransferInProgress = false;
        }
    }

    pub fn StartOAMTransfer(self: *DMA, AddressHi : u8) void{
        self.OAMTransferInProgress = true;
        self.oamStartAddress = @as(u16,AddressHi);
        self.oamCurrentIndex = 0x00;
    }

    pub fn oamTick(self: *DMA)void{
        
        if(!self.OAMTransferInProgress) return;

        const oamAddress:u16 = (self.oamStartAddress << 8) | self.oamCurrentIndex;
        self.oam.write(self.oamCurrentIndex, self.Emu.bus.read(oamAddress));
        self.oamCurrentIndex +%= 1;

        if(self.oamCurrentIndex > 0x9F){
            self.oamCurrentIndex = 0x00;
            self.OAMTransferInProgress = false;
        }
    }

    pub fn Hblank(self: *DMA)void{
        if(!self.VRAMTransferInProgress or !(self.HDMA5.TransferMode == .Hblank) or !self.Emu.CGBMode) return;

        var i:u16 = 0;
        while(i < 0x10) : (i +=1){
            const Src: u8 = self.Emu.bus.read(self.HDMA12+%i);
            self.vram.write(self.HDMA34+%i, Src);
        }

        self.HDMA12 +%= 0x10;
        self.HDMA34 +%= 0x10;


        self.HDMA5.TransferLength -%= 1;

        if(self.HDMA5.TransferLength == 0x7F){
            self.VRAMTransferInProgress = false;
            return;
        }

    }

    pub fn GeneralPurpose(self: *DMA)void{
        if(!self.VRAMTransferInProgress or !(self.HDMA5.TransferMode == .GeneralPurpose) or !self.Emu.CGBMode) return;
        
        var i:u16 = 0;
        while(i < ((@as(u16,self.HDMA5.TransferLength) + 1) * 0x10)) : (i+=1){
            const Src : u8 = self.Emu.bus.read(self.HDMA12+%i);
            self.vram.write(self.HDMA34+%i, Src);
        }

        self.VRAMTransferInProgress = false;
        self.HDMA5 = @bitCast(@as(u8,0xFF));
    }
};

const VRAM_DMA_Control = packed struct {
    TransferLength : u7,
    TransferMode : VRAMTransferMode,
};

const VRAMTransferMode = enum(u1) {
    GeneralPurpose,
    Hblank,
};