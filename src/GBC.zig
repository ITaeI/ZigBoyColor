const std = @import("std");
const SM83 = @import("SM83.zig").SM83;
const MMap = @import("MemoryMap.zig").MemoryMap;
const Cart = @import("Cartridge.zig").Cartridge;
const PPU = @import("PPU.zig").PPU;
const Timer  = @import("Timer.zig").Timer;
const DMA = @import("DMA.zig").DMA;

const GUI = @import("GUI.zig").GUI;

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
    SwapState: bool = false,

    ticks : u64 = 0,
    pub fn init(self: *GBC, parentPtr: *GUI, Rom: []const u8) !void{

        // Here we Initalize the Cartridge and load the rom
        self.cart = Cart{.GBC = self,.alloc = std.heap.page_allocator};
        try self.cart.load(Rom);

        self.cpu = SM83.init(self);
        // need to setup Opcode Tables
        self.cpu.setupOpcodeTables();

        self.ppu = PPU.init(self,parentPtr);
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

            self.ticks += 1;
        }

        // oam dma
        self.dma.oamTick();

        if(self.DoubleSpeed.Active and self.ticks >= 4194304*2 ){
            self.cart.TimerTick();
            self.ticks = 0;
        }
        else if(self.ticks >= 4194304){
            self.cart.TimerTick();
            self.ticks = 0;
        }
    }

    pub fn SwapSpeed(self : *GBC)void{
        // for 2050 M cycles after speed swap the cpu stops
        // div does not tick, and ppu does odd stuff we can ignore
        self.SwapState = true;
        for(0..2050) |_|{
            self.cycle();
        }
        self.SwapState = false;
        self.DoubleSpeed.Active = !self.DoubleSpeed.Active;
        self.DoubleSpeed.Armed = false;
    }
};

const KEY1 = packed struct {
    Armed : bool,
    padding : u6,
    Active : bool,
};