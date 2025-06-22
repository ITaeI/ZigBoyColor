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
    quit : bool = false,
    DmgMode : bool = false,
    DoubleSpeed : bool = false,

    // Memory allocator
    allocator : std.mem.Allocator = undefined,

    pub fn init(self: *GBC) void{

        self.cpu = SM83.init(self);
        // need to setup Opcode Tables
        self.cpu.setupOpcodeTables();

        self.ppu = PPU.init(self);
        self.cart = Cart{.alloc = std.heap.page_allocator};
        self.bus = MMap.init(self);
        self.timer = Timer.init(self);
        self.dma = DMA.init(self);

    }

    pub fn Run(self: *GBC, Rom: []const u8) !void {

        // Here we load the cartridge
        try self.cart.load(Rom);

        // This is where the cpu will be stepping
        while(!self.quit){
            self.cpu.step(); 
        }

        // Free any memory allocated to the heap
        self.deinit();
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
            if(!self.DoubleSpeed)
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