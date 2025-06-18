const std = @import("std");
const SM83 = @import("SM83.zig").SM83;
const MMap = @import("MemoryMap.zig").MemoryMap;
const Cart = @import("Cartridge.zig").Cartridge;
const PPU = @import("PPU.zig").PPU;

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

    // Here is the APU

    // Useful control variables
    quit : bool = false,
    DmgMode : bool = false,

    // Memory allocator
    allocator : std.mem.Allocator = undefined,

    pub fn init(self: *GBC) void{

        self.cpu = SM83.init(self);
        self.ppu = PPU.init(self);
        self.cart = Cart{.alloc = std.heap.page_allocator};
        self.bus = MMap.init(self);

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

    pub fn cycle() void{

        // APU
        // PPU
        // DMA 
        // Timer
    }
};