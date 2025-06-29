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

    var oamStartAddress: u16 = undefined;
    var oamCurrentIndex: u16 = undefined;

    var HDMA12 : u16 = 0xFFFF;
    var HDMA34 : u16 = 0xFFFF;
    var HDMA5 : VRAM_DMA_Control = undefined;


    pub fn init(parentPtr : *GBC) DMA{

        HDMA5 = @bitCast(@as(u8,0xFF));

        return DMA{
            .Emu  = parentPtr,
            .vram = &parentPtr.ppu.vram,
            .oam = &parentPtr.ppu.oam,
        };
    }

    pub fn write(self : *DMA, address: u16, data : u8)void{

        if(!self.Emu.CGBMode) return;
        switch (address) {
            0xFF51 => HDMA12 = (HDMA12&0x80FF) | (@as(u16,data) << 8),
            0xFF52 => HDMA12 = (HDMA12&0xFF00) | @as(u16,data&0xF0),
            0xFF53 => HDMA34 = (HDMA34&0x80FF) | (@as(u16,data) << 8),
            0xFF54 => HDMA34 = (HDMA34&0xFF00) | @as(u16,data&0xF0),
            0xFF55 => self.startVRAMTransfer(data),
            else => {},        
        }

    }

    pub fn read(self : *DMA)u8{
        if(!self.Emu.CGBMode) return 0xFF;
        const active : u8 = @as(u8,@intFromBool(self.VRAMTransferInProgress)) << 7;
        return ((~active) & 0x80) | @as(u8,@bitCast(HDMA5));
    }

    fn startVRAMTransfer(self: *DMA,data:u8)void{

        const PrevMode = HDMA5.TransferMode;
        const PrevActivity = self.VRAMTransferInProgress;
        self.VRAMTransferInProgress = true;
        HDMA5 = @bitCast(data);

        // you can cancel a active hblank dma by writing 0 to bit 7
        if((PrevMode == .Hblank and PrevActivity) and HDMA5.TransferMode == .GeneralPurpose){
            self.VRAMTransferInProgress = false;
        }
    }

    pub fn StartOAMTransfer(self: *DMA, AddressHi : u8) void{
        self.OAMTransferInProgress = true;
        oamStartAddress = @as(u16,AddressHi);
        oamCurrentIndex = 0x00;
    }

    pub fn oamTick(self: *DMA)void{
        
        if(!self.OAMTransferInProgress) return;

        const oamAddress:u16 = (oamStartAddress << 8) | oamCurrentIndex;
        self.oam.write(oamCurrentIndex, self.Emu.bus.read(oamAddress));
        oamCurrentIndex +%= 1;

        if(oamCurrentIndex > 0x9F){
            oamCurrentIndex = 0x00;
            self.OAMTransferInProgress = false;
        }
    }

    pub fn Hblank(self: *DMA)void{
        if(!self.VRAMTransferInProgress or !(HDMA5.TransferMode == .Hblank) or !self.Emu.CGBMode) return;

        var i:u16 = 0;
        while(i < 0x10) : (i +=1){
            const Src: u8 = self.Emu.bus.read(HDMA12+i);
            self.vram.write(HDMA34+i, Src);
        }

        HDMA12 +%= 0x10;
        HDMA34 +%= 0x10;


        if(HDMA5.TransferLength == 0x00){
            self.VRAMTransferInProgress = false;
            return;
        }

        HDMA5.TransferLength -= 1;
    }

    pub fn GeneralPurpose(self: *DMA)void{
        if(!self.VRAMTransferInProgress or !(HDMA5.TransferMode == .GeneralPurpose) or !self.Emu.CGBMode) return;
        
        var i:u16 = 0;
        while(i < ((@as(u16,HDMA5.TransferLength) + 1) * 0x10)) : (i+=1){
            const Src : u8 = self.Emu.bus.read(HDMA12+i);
            self.vram.write(HDMA34+i, Src);
        }

        self.VRAMTransferInProgress = false;
        HDMA5 = @bitCast(@as(u8,0xFF));
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