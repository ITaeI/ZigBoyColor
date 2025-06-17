const std = @import("std");


pub const Cartridge = struct {

    // File name : Useful for creating save files
    fileName : []const u8 = undefined,
    // Header : Gives us useful data on what rom is entered
    header   : *Header = undefined,
    // Rom Data : Exactly that the binary of the rom
    romData  : []u8 = undefined,

    // Memory Bank Controller Object
    mbc : MBC = undefined, // this maps our reads and our writes

    // allocator to extract rom data to the heap
    alloc : std.mem.Allocator,

    pub fn load(self: *Cartridge,filePath : []const u8) !void{

        // Open file
        const file = try std.fs.openFileAbsolute(
            filePath, 
            .{.mode = .read_only}
        );
        // defer closing file
        defer file.close();
        // also close if an error is thrown
        errdefer file.close();

        // Load rom data into struct slice
        const stat = try file.stat();
        self.romData = try file.readToEndAlloc(self.alloc, stat.size);

        // Extract Our header information
        self.header = @ptrCast(@alignCast(&self.romData[0x100]));

        // set our memory bank controller
        self.mbc = switch (self.header.cart_type) {
            0 => MBC{.Rom = ROM{}},
            0x1 => MBC{.MBC1 = MBC1{}},
            0x2 => MBC{.MBC1 = MBC1{.Ram = true}},
            0x3 => MBC{.MBC1 = MBC1{.Ram = true, .Battery = true}},
            0x5 => MBC{.MBC2 = MBC2{}},
            0x6 => MBC{.MBC2 = MBC2{.Battery = true}},
            0x8 => MBC{.Rom = ROM{.Ram = true}},
            0x9 => MBC{.Rom = ROM{.Ram = true, .Battery = true}},
            0xF => MBC{.MBC3 = MBC3{.Timer = true, .Battery = true}},
            0x10 => MBC{.MBC3 = MBC3{.Ram = true, .Timer = true, .Battery = true}},
            0x11 => MBC{.MBC3 = MBC3{}},
            0x12 => MBC{.MBC3 = MBC3{.Ram = true}},
            0x13 => MBC{.MBC3 = MBC3{.Battery = true}},
            else => return error.UnsupportedMemoryBankController,
        };


    }

    /// Used to free rom data
    pub fn deinit(self : *Cartridge) void {
        self.alloc.free(self.romData);
    }

    // Tagged Union Wrappers

    pub fn read(self : *Cartridge, address: u16) u8 {
        return self.mbc.read(address);
    }

    pub fn write(self : *Cartridge, address: u16, data : u8) u8{
        self.write(address, data);
    }

    fn hasBattery(self: *Cartridge)bool{
        return self.mbc.hasBattery();
    }
};

const Header = packed struct(u640) {
    entry           : u32,
    nintendo_logo   : u384,
    Title           : u128,
    Licensee_Code   : u16,
    sgb_flag        : u8,
    cart_type       : u8,
    rom_size        : u8,
    ram_size        : u8,
    dest_code       : u8,
    lic_code        : u8,
    version         : u8,
    checksum        : u8,
    global_checksum : u16,
};



// Memory Bank Controllers

const MBC = union(enum){
    Rom  : ROM,
    MBC1 : MBC1,
    MBC2 : MBC2,
    MBC3 : MBC3,

    fn read(self : *MBC, address: u16)u8{
        return switch (self) {
            inline else => |mbc| mbc.read(address),
        };
    }

    fn write(self : *MBC, address: u16,data: u8)void{
        switch (self) {
            inline else => |mbc| mbc.write(address,data),
        }
    }

    fn hasBattery(self: *MBC) !bool{
        switch (self) {
            .Rom => false,
            .MBC1 => |mbc| mbc.Battery,
            .MBC2 => false,
            .MBC3 => |mbc| mbc.Battery,
            else => {},
        }
    }

};

/// Rom only
const ROM = struct {

    Ram : bool = false,
    Battery : bool = false,

    pub fn read(address: u16) u8{
        _ = address;
    }

    pub fn write(address : u16, data : u8) void {
        _ = address;
        _ = data;
    }
};

const MBC1 = struct {

    Ram : bool = false,
    Battery : bool = false,

    pub fn read(address: u16) u8{
        _ = address;
    }

    pub fn write(address : u16, data : u8) void {
        _ = address;
        _ = data;
    }
};

const MBC2 = struct {

    Ram : bool = false,
    Battery : bool = false,

    pub fn read(address: u16) u8{
        _ = address;
    }

    pub fn write(address : u16, data : u8) void {
        _ = address;
        _ = data;
    }
};

const MBC3 = struct {

    Ram : bool = false,
    Battery : bool = false,
    Timer : bool = false,

    pub fn read(address: u16) u8{
        _ = address;
    }

    pub fn write(address : u16, data : u8) void {
        _ = address;
        _ = data;
    }
};