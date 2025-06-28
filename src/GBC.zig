const std = @import("std");
const SM83 = @import("SM83.zig").SM83;
const MMap = @import("MemoryMap.zig").MemoryMap;
const Cart = @import("Cartridge.zig").Cartridge;
const PPU = @import("PPU.zig").PPU;
const Timer  = @import("Timer.zig").Timer;
const DMA = @import("DMA.zig").DMA;

pub const GBC = struct {

    // Here is the CPU
    cpu : SM83 = undefined,
    // Here is the PPU
    ppu : PPU = undefined,
    // Here is the Cartridge
    cart : Cart = undefined,

    // Here is the Bus/Memory Map
    bus : MMap = undefined,
    // Here is the timer
    timer : Timer = undefined,
    // Here is the APU

    // DMA module
    dma : DMA = undefined,
    // Useful control variables
    FrameFinished : bool = false,
    CGBMode : bool = false,

    // Double speed variables
    DoubleSpeed : KEY1 = @bitCast(@as(u8,0x7E)),

    pub fn init(self: *GBC, Rom: []const u8) !void{

        self.FrameFinished = false;
        self.CGBMode = false;

        // Double speed variables
        self.DoubleSpeed = @bitCast(@as(u8,0x7E));

        // Here we Initalize the Cartridge and load the rom
        self.cart = Cart{.GBC = self,.alloc = std.heap.page_allocator};
        try self.cart.load(Rom);

        self.cpu = SM83.init(self);
        // need to setup Opcode Tables
        self.cpu.setupOpcodeTables();

        self.ppu = PPU.init(self);
        self.timer = Timer.init(self);
        self.dma = DMA.init(self);
        self.bus = MMap.init(self);
    }

    pub fn Run(self: *GBC) void {

        // This is where the cpu will be stepping
        while(!self.FrameFinished){
            self.cpu.step(); 
        }
    }

    pub fn deinit(self: *GBC)void{
        self.cart.deinit();
    }

    pub fn cycle(self: *GBC) void{
        
        var i : u8 = 0;
        while(i < 4) : (i += 1){
            self.timer.tick();

            // the ppu "Slows to half" in double speed mode
            // so does the apu (in progress)
            if(!self.DoubleSpeed.Active)
            {
                self.ppu.tick();
            }
            else if(i == 1 or i == 3){
                self.ppu.tick();
            }
        }
        // vram dma (not affected by double speed as it is a single data transfer)
        self.dma.GeneralPurpose();
        // oam dma
        self.dma.oamTick();
    }
};

const KEY1 = packed struct {
    Armed : bool,
    padding : u6,
    Active : bool,
};