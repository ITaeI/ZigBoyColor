const std = @import("std");


pub const Cartridge = struct {

    // File name : Useful for creating save files
    filePath : []const u8 = undefined,
    // Header : Gives us useful data on what rom is entered
    header   : *Header = undefined,
    // Rom Data : Exactly that the binary of the rom
    romData  : []u8 = undefined,

    // Memory Bank Controller Object
    mbc : MBC = undefined, // this maps our reads and our writes

    // allocator to extract rom data to the heap
    alloc : std.mem.Allocator,

    pub fn load(self: *Cartridge,filePath : []const u8) !void{

        // Save File Path
        self.filePath = filePath;
        
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
            0 => MBC{.Rom = ROM{.Header = self.header,.Data = &self.romData}},
            0x1 => MBC{.MBC1 = MBC1{.Header = self.header,.Data = &self.romData,}},
            0x2 => MBC{.MBC1 = MBC1{.Header = self.header,.Data = &self.romData,.HasRam= true}},
            0x3 => MBC{.MBC1 = MBC1{.Header = self.header,.Data = &self.romData,.HasRam= true, .HasBattery = true}},
            0x5 => MBC{.MBC2 = MBC2{.Header = self.header,.Data = &self.romData,}},
            0x6 => MBC{.MBC2 = MBC2{.Header = self.header,.Data = &self.romData,.HasBattery = true}},
            0x8 => MBC{.Rom = ROM{.Header = self.header,.Data = &self.romData,.HasRam= true}},
            0x9 => MBC{.Rom = ROM{.Header = self.header,.Data = &self.romData,.HasRam= true, .HasBattery = true}},
            0xF => MBC{.MBC3 = MBC3{.Header = self.header,.Data = &self.romData,.HasTimer = true, .HasBattery = true}},
            0x10 => MBC{.MBC3 = MBC3{.Header = self.header,.Data = &self.romData,.HasRam= true, .HasTimer = true, .HasBattery = true}},
            0x11 => MBC{.MBC3 = MBC3{.Header = self.header,.Data = &self.romData,}},
            0x12 => MBC{.MBC3 = MBC3{.Header = self.header,.Data = &self.romData,.HasRam= true}},
            0x13 => MBC{.MBC3 = MBC3{.Header = self.header,.Data = &self.romData,.HasBattery = true}},
            else => return error.UnsupportedMemoryBankController,
        };

        // Check if our chipset has battery buffered ram
        // reload save if it does
        if(self.mbc.hasBattery()){
            self.mbc.reloadSave(self.filePath);
        }
    }

    /// Used to free rom data
    /// And save Battery Buffered Ram
    pub fn deinit(self : *Cartridge) void {

        // Check if Save is possible
        if(self.mbc.hasBattery()){
            // Save the game/RAM
            self.mbc.save(self.filePath);
        }
        // Free the rom data
        self.alloc.free(self.romData);
    }

    // Tagged Union Wrappers

    pub fn read(self : *Cartridge, address: u16) u8 {
        return self.mbc.read(address);
    }

    pub fn write(self : *Cartridge, address: u16, data : u8) void{
        self.mbc.write(address, data);
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
        return switch (self.*) {
            inline else => |mbc| mbc.read(address),
        };
    }

    fn write(self : *MBC, address: u16,data: u8)void{
        switch (self.*) {
            inline else => |mbc| mbc.write(address,data),
        }
    }

    fn save(self : *MBC, filePath : []const u8) void{
        switch (self.*) {
            inline else => |mbc| mbc.save(filePath) catch |e| std.debug.print("Unable to Save due to {}", .{e}),
        }
    }

    fn reloadSave(self : *MBC, filePath : []const u8) void{
        switch (self.*) {
            inline else => |mbc| mbc.reloadSave(filePath) catch |e| std.debug.print("Unable to Reload Save due to {}", .{e}),
        }
    }

    fn hasBattery(self: *MBC) bool{
        return switch (self.*) {
            inline else => |mbc| mbc.HasBattery,
        };
    }

};

fn changeFileType(allocator: std.mem.Allocator, fileIn: []const u8) ![]const u8 {

    const GBneedle = ".gb";
    const GBCneedle = ".gbc";

    const saveFormat = ".sav";

    const StringBuffer = try std.mem.replaceOwned(
    u8, 
    allocator, 
    fileIn, 
    if (std.mem.endsWith(u8, fileIn,GBCneedle)) GBCneedle else GBneedle, 
    saveFormat
    ); 


    return StringBuffer;
}

/// Rom only
const ROM = struct {

    HasRam : bool = false,
    HasBattery : bool = false,

    Data : *[]u8,
    Header : *Header,

    // Rom only has a maximum of 8 kib of RAM
    var RAM : [0x2000]u8 = [_]u8{0} ** 0x2000;

    // No Banking necessary for ROM MBC
    pub fn read(self: ROM,address: u16) u8{

        return switch (address) {
            0...0x7FFF => self.Data.*[address],
            0xA000...0xBFFF => RAM[address - 0xA000],
            else => 0xFF,
        };
    }

    pub fn write(self: ROM,address : u16, data : u8) void {
        switch (address) {
            0...0x7FFF => self.Data.*[address] = data,
            0xA000...0xBFFF => RAM[address - 0xA000] = data,
            else => {},
        }
    }

    pub fn save(self: ROM ,filePath : []const u8) !void{
        _= self;
        try saveFile(filePath, RAM[0..]);
    }

    pub fn reloadSave(self: ROM ,filePath : []const u8) !void{
        _= self;
        try reloadsaveFile(filePath, RAM[0..]);
    }
};

const MBC1 = struct {

    HasRam : bool = false,
    HasBattery : bool = false,

    Data : *[]u8,
    Header : *Header,

    var RAM : [0x8000]u8 = [_]u8{0} ** 0x8000;
    var currentRamBank: u8 = 0;
    var currentRomBank: u8 = 1;
    var ZeroBank: u8 = 0;
    var HighBank: u8 = 0;

    // Useful Flags
    var modeFlag : bool = false;
    var ramEnabled : bool = false;

    pub fn read(self: MBC1,address: u16) u8{

        return switch (address) {
            0...0x3FFF => if (!modeFlag) self.Data.*[address] else self.Data.*[address + (ZeroBank*0x4000)],
            0x4000...0x7FFF => self.Data.*[address - 0x4000 + (HighBank * 0x4000)],
            0xA000...0xBFFF => blk :{
                if(!ramEnabled){ 
                    break :blk 0xFF;
                }
                
                if(self.Header.ram_size >= 0x03){
                    break :blk if(modeFlag) RAM[(address - 0xA000) + currentRamBank * 0x2000] else RAM[address - 0xA000];
                }
                else {
                    break :blk RAM[address - 0xA000];
                }

            },
            else => 0xFF,
        };
    }

    pub fn write(self: MBC1,address : u16, data : u8) void {
        switch (address) {
            0...0x1FFF => ramEnabled = ((data & 0xF) == 0xA),
            0x2000...0x3FFF => {
                if(data == 0x00) currentRomBank = 1;
                currentRomBank = switch (self.Header.rom_size) {
                    0 => 1,
                    1 => data & 0x3,
                    2 => data & 0x7,
                    3 => data & 0xF,
                    4...6 => data & 0x1F,
                    else => 1,
                };
            },
            0x4000...0x5FFF => currentRamBank = (currentRamBank & 0xFC) | (data & 0x3),
            0x6000...0x7FFF => modeFlag = @bitCast(@as(u1,@truncate(data))),
            0xA000...0xBFFF => {
                if(!ramEnabled) return;

                if(self.Header.ram_size >= 0x3){
                    if(modeFlag){
                        RAM[(address - 0xA000) + currentRamBank * 0x2000] = data;
                    }else{
                        RAM[address - 0xA000] = data;
                    }
                }
                else{
                    RAM[(address - 0xA000) & 0x1FFF] = data;
                }
            },
            else => {},
        }
    }

    fn calculateBanks(self: MBC1) void{
        switch (self.Header.rom_size) {
            0...4 => {
                HighBank = currentRomBank;  
                ZeroBank = 0;
            },
            5 => {
                HighBank = (currentRomBank & 0b11011111) | ((currentRamBank & 0x1) << 5);
                ZeroBank = (currentRamBank & 0x1) << 5;
            },
            6 => {
                HighBank = (currentRomBank & 0b10011111) | ((currentRamBank & 0x3) << 5);
                ZeroBank = (currentRamBank & 0x3) << 5;
            },
            else => currentRomBank,
        }
    }

    pub fn save(self: MBC1 ,filePath : []const u8) !void{
        _= self;
        try saveFile(filePath, RAM[0..]);
    }

    pub fn reloadSave(self: MBC1 ,filePath : []const u8) !void{
        _= self;
        try reloadsaveFile(filePath, RAM[0..]);
    }
};

const MBC2 = struct {

    HasBattery : bool = false,
    Data : *[]u8,
    Header : *Header,

    var RAM : [512]u8 = [_]u8{0} ** 512;
    var currentRomBank: u8 = 1;
    var currentRamBank: u8 = 0;

    var ramEnabled : bool = false;

    pub fn read(self : MBC2,address: u16) u8{
        return switch (address) {
            0x4000...0x7FFF => self.Data.*[(address-0x4000) + (currentRomBank * 0x4000)],
            0xA000...0xBFFF => blk:{
                if(!ramEnabled) break :blk 0xFF;
                break :blk 0xF0 | (RAM[((address - 0xA000)&0x1FF) + (currentRamBank * 0x2000)] & 0xF);
            },
            else => ROM[address],
        };
    }

    pub fn write(self : MBC2,address : u16, data : u8) void {
        switch (address) {
            0...0x3FFF =>{
                if(((address >> 8) & 1) == 0){
                    ramEnabled = ((data&0xF) == 0xA);
                }
                else {
                    currentRomBank = if(data != 0) data & 0xF else 1;
                }
            },
            0xA000...0xBFFF => {
                if(!ramEnabled) return;
                RAM[(address-0xA000)&0x1FF] = data; // only half bytes are stored
            }
        }
        // discard since we dont need header data
        _  = self;
    }

    pub fn save(self: MBC2 ,filePath : []const u8) !void{
        _= self;
        try saveFile(filePath, RAM[0..]);
    }

    pub fn reloadSave(self: MBC2 ,filePath : []const u8) !void{
        _= self;
        try reloadsaveFile(filePath, RAM[0..]);
    }
};

const MBC3 = struct {

    HasRam : bool = false,
    HasBattery : bool = false,
    HasTimer : bool = false,

    Data : *[]u8,
    Header : *Header,

    var RAM : [0x8000]u8 = [_]u8{0} ** 0x8000;
    var currentRomBank : u8 = 1;
    var currentRamBank : u8 = 0;
    var currentRTCreg  : u8 = 0;

    var ramEnabled: bool = false;
    var ClockRegisterMapped: bool = false;
    var latchOccured : bool = false;

    var RTC = RTC_Regs{};
    var RTCLatched = RTC_Regs{};

    var prevInput: u8 = undefined;

    const RTC_Regs = struct {
        s : u8 = 0,
        m : u8 = 0,
        h : u8 = 0,
        DL: u8 = 0,
        DH: u8 = 0,
    };

    pub fn read(self:MBC3,address: u16) u8{
        return switch (address) {
            0...0x3FFF => self.Data.*[address],
            0x4000...0x7FFF => self.Data.*[(address-0x4000) + (currentRomBank * 0x4000)],
            0xA000...0xBFFF => blk:{
                if(ClockRegisterMapped){
                    if(!latchOccured) break :blk 0xFF;
                    break :blk switch (currentRTCreg) {
                        8 => 0b11000000 | RTCLatched.s,
                        9 => 0b11000000 | RTCLatched.m,
                        0xA => 0b11100000 | RTCLatched.h,
                        0xB => RTCLatched.DL,
                        0xC => 0b00111110 | RTCLatched.DH,
                        else => unreachable, // TODO: most likely can just return rom data
                    };
                }
                else {
                    if(!ramEnabled) break :blk 0xFF;
                    break :blk RAM[(address-0xA000) + (currentRamBank * 0x2000)];
                }
            }
        };
    }

    pub fn write(self:MBC3,address : u16, data : u8) void {
        switch (address) {
            0...0x1FFF => ramEnabled = ((data&0xF) == 0xA),
            0x2000...0x3FFF => currentRomBank = if(data == 0) 1 else data & 0x7F,
            0x4000...0x5FFF =>{
                if(data <= 3){
                    ClockRegisterMapped = false;
                    currentRamBank = data;
                }
                else {
                    ClockRegisterMapped = true;
                    currentRTCreg = data;
                }
            },
            0x6000...0x7FFF =>{
                if(prevInput == 0 and data == 1){
                    RTCLatched = RTC;
                    latchOccured = true;
                }
                prevInput = data;
            },
            0xA000...0xBFFF =>{
                if(ClockRegisterMapped){
                    switch (currentRTCreg) {
                        0x08 => {
                            RTCLatched.s = data & 0b00111111;
                            RTC.s = data & 0b00111111;
                            // Emu->ticks = 0; // resets sub second counter (commented out, as Emu is undefined)
                        },
                        0x09 => {
                            RTCLatched.m = data & 0b00111111;
                            RTC.m = data & 0b00111111;
                        },
                        0x0A => {
                            RTCLatched.h = data & 0b00011111;
                            RTC.h = data & 0b00011111;
                        },
                        0x0B => {
                            RTCLatched.DL = data;
                            RTC.DL = data;
                        },
                        0x0C => {
                            RTCLatched.DH = data & 0b11000001;
                            RTC.DH = data & 0b11000001;
                        },
                        else => {},
                    }
                }
                else{
                    if(!ramEnabled) return;
                    RAM[(address-0xA000) + (currentRamBank * 0x2000)] = data;
                }
            }
        }
        _ = self;
    }

    pub fn save(self: MBC3 ,filePath : []const u8) !void{
        _= self;
        try saveFile(filePath, RAM[0..]);
    }

    pub fn reloadSave(self: MBC3 ,filePath : []const u8) !void{
        _= self;
        try reloadsaveFile(filePath, RAM[0..]);
    }
};

fn saveFile(filePath: []const u8, ramSlice : []u8) !void{

    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const saveFilePath = try changeFileType(allocator,filePath);
    defer allocator.free(saveFilePath);

    var file = std.fs.createFileAbsolute(saveFilePath,.{.read = true})

    // if save file alread exists open that instead
    catch |err| switch (err) {
        error.PathAlreadyExists => try std.fs.openFileAbsolute(saveFilePath, .{ .mode = .write_only }),
        else => unreachable,
    }; 

    defer file.close();
    errdefer file.close();

    try file.seekTo(0);
    _ = try file.writeAll(ramSlice);
}

fn reloadsaveFile(filePath: []const u8, ramSlice : []u8) !void{

    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const saveFilePath = try changeFileType(allocator,filePath);
    defer allocator.free(saveFilePath);

    const file = try std.fs.openFileAbsolute(saveFilePath, .{ .mode = .read_only });

    defer file.close();
    errdefer file.close();

    try file.seekTo(0);
    _ = try file.readAll(ramSlice);
}

test "File Change" {

    // Unput a gbc or gb file name
    const alloc = std.testing.allocator;
    const newfile = try changeFileType(alloc,"documents/Blah.gbc");
    defer alloc.free(newfile);

    // Should output a .save file of the same file
    std.debug.print("{s}", .{newfile});
    try std.testing.expect(std.mem.eql(u8, "documents/Blah.sav", newfile));
}

test "File Save"{

    var rom : MBC1 = MBC1{.HasBattery = true, .HasRam = true};

    rom.reloadSave("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Legend of Zelda, The - Link's Awakening (U) (V1.2) [!].gb")
    catch |err| std.debug.print("Error: {}", .{err});
    rom.save("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Legend of Zelda, The - Link's Awakening (U) (V1.2) [!].gb")
    catch |err| std.debug.print("Error: {}", .{err});

}

test "Load Rom" {

    const alloc = std.testing.allocator;
    var cart = Cartridge{.alloc = alloc};


    try cart.load("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Legend of Zelda, The - Link's Awakening (U) (V1.2) [!].gb");
    try std.testing.expect(std.mem.eql(u8, "C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Legend of Zelda, The - Link's Awakening (U) (V1.2) [!].gb", cart.filePath));
    // the rom is placed on the heap so it needs to be freed before end of program
    defer alloc.free(cart.romData);

    // The Title of this can be parsed like this
    const title_bytes = std.mem.asBytes(&cart.header.Title);
    const title = std.mem.trimRight(u8, title_bytes, "\x00");
   
    try std.testing.expect(std.mem.eql(u8,"ZELDA",title));

}

test "Read and Write"{

    const alloc = std.testing.allocator;
    var cart = Cartridge{.alloc = alloc};


    try cart.load("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Tetris (JUE) (V1.1) [!].gb");
    try std.testing.expect(std.mem.eql(u8, "C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Tetris (JUE) (V1.1) [!].gb", cart.filePath));
    // the rom is placed on the heap so it needs to be freed before end of program
    defer alloc.free(cart.romData);

    cart.write(0x0000, 0xFF);
    const out = cart.read(0x0000);

    try std.testing.expect(out == 0xFF);
}