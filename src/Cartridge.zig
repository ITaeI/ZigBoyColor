const std = @import("std");
const GBC = @import("GBC.zig").GBC;


pub const Cartridge = struct {

    // GBC pointer 
    GBC : *GBC,
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
        const file = try std.fs.cwd().openFile(
            filePath, 
            .{.mode = .read_only}
        );

        // defer closing file
        defer file.close();

        // Load rom data into struct slice
        const stat = try file.stat();
        self.romData = try file.readToEndAlloc(self.alloc, stat.size);

        errdefer self.alloc.free(self.romData);
        // Extract Our header information
        self.header = @ptrCast(@alignCast(&self.romData[0x100]));

        // set our memory bank controller

        std.debug.print("Cart Type : {x}", .{self.header.cart_type});
        self.mbc = switch (self.header.cart_type) {
            0 => MBC{.Rom = ROM{.Header = self.header,.Data = &self.romData}},
            0x1 => MBC{.MBC1 = MBC1{.Header = self.header,.Data = &self.romData,}},
            0x2 => MBC{.MBC1 = MBC1{.Header = self.header,.Data = &self.romData,.HasRam= true}},
            0x3 => MBC{.MBC1 = MBC1{.Header = self.header,.Data = &self.romData,.HasRam= true, .HasBattery = true}},
            0x5 => MBC{.MBC2 = MBC2{.Header = self.header,.Data = &self.romData,}},
            0x6 => MBC{.MBC2 = MBC2{.Header = self.header,.Data = &self.romData,.HasBattery = true}},
            0x8 => MBC{.Rom = ROM{.Header = self.header,.Data = &self.romData,.HasRam= true}},
            0x9 => MBC{.Rom = ROM{.Header = self.header,.Data = &self.romData,.HasRam= true, .HasBattery = true}},
            0xF => MBC{.MBC3 = MBC3{.Emu = self.GBC,.Header = self.header,.Data = &self.romData,.HasTimer = true, .HasBattery = true}},
            0x10 => MBC{.MBC3 = MBC3{.Emu = self.GBC,.Header = self.header,.Data = &self.romData,.HasRam= true, .HasTimer = true, .HasBattery = true}},
            0x11 => MBC{.MBC3 = MBC3{.Emu = self.GBC,.Header = self.header,.Data = &self.romData,}},
            0x12 => MBC{.MBC3 = MBC3{.Emu = self.GBC,.Header = self.header,.Data = &self.romData,.HasRam= true}},
            0x13 => MBC{.MBC3 = MBC3{.Emu = self.GBC, .Header = self.header,.Data = &self.romData,.HasBattery = true}},
            0x19 => MBC{.MBC5 = MBC5{.Header = self.header,.Data = &self.romData,}},
            0x1A => MBC{.MBC5 = MBC5{.Header = self.header,.Data = &self.romData,.HasRam= true}},
            0x1B => MBC{.MBC5 = MBC5{.Header = self.header,.Data = &self.romData,.HasRam= true, .HasBattery = true}},
            0x1C => MBC{.MBC5 = MBC5{.Header = self.header,.Data = &self.romData,.HasRumble = true}},
            0x1D => MBC{.MBC5 = MBC5{.Header = self.header,.Data = &self.romData,.HasRumble = true, .HasRam= true}},
            0x1E => MBC{.MBC5 = MBC5{.Header = self.header,.Data = &self.romData,.HasRumble = true, .HasRam= true , .HasBattery = true}},
            else => return error.UnsupportedMemoryBankController,
        };
        // Check to see if the CGB Flag is set (Last byte of Title is CGB flag)
        if(self.romData[0x143]  == 0x80 or self.romData[0x143]  == 0xC0){
            self.GBC.CGBMode = true;
        }


        // Check if our chipset has battery buffered ram
        // reload save if it does

        self.ReloadSave(self.filePath);
    }

    /// Used to free rom data
    /// And save Battery Buffered Ram
    pub fn deinit(self : *Cartridge) void {

        self.save(self.filePath);
        // Free the rom data
        
        if (self.romData.len > 0) self.alloc.free(self.romData);
    }

    // Tagged Union Wrappers (Easier than having them in union)

    pub fn read(self : *Cartridge, address: u16) u8 {

        return switch (self.mbc) {
            inline else => |*mbc| mbc.read(address),
        };
    }

    pub fn write(self : *Cartridge, address: u16, data : u8) void{

        switch (self.mbc) {
            inline else => |*mbc| mbc.write(address,data),
        }
    }

    fn save(self : *Cartridge, filePath: []const u8) void{
        switch (self.mbc) {
            inline else => |*mbc| {
                if (mbc.HasBattery) mbc.save(filePath) catch |e| std.debug.print("Unable to Save due to {}", .{e});
            },
        }
    }

    fn ReloadSave(self : *Cartridge, filePath: []const u8) void{
        switch (self.mbc) {
            inline else => |*mbc| {
                if (mbc.HasBattery) mbc.reloadSave(filePath) catch |e| std.debug.print("Unable to Save due to {}", .{e});
            },
        }
    }

    pub fn TimerTick(self : *Cartridge) void{

        switch (self.mbc) {
            .MBC3 => |*mbc| mbc.tick(),
            else => {},
        }
    }
};

const Header = packed struct(u640) {
    entry           : u32,
    nintendo_logo   : u384,
    Title           : u128, // the last byte of this is the cgb flag
    New_Licensee_Code   : u16,
    sgb_flag        : u8,
    cart_type       : u8,
    rom_size        : u8,
    ram_size        : u8,
    dest_code       : u8,
    Old_lic_code        : u8,
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
    MBC5 : MBC5,
};

fn changeFileType(allocator: std.mem.Allocator, fileIn: []const u8, extension: []const u8) ![]const u8 {

    const GBneedle = ".gb";
    const GBCneedle = ".gbc";

    const StringBuffer = try std.mem.replaceOwned(
    u8, 
    allocator, 
    fileIn, 
    if (std.mem.endsWith(u8, fileIn,GBCneedle)) GBCneedle else GBneedle, 
    extension
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
    RAM : [0x2000]u8 = [_]u8{0} ** 0x2000,

    // No Banking necessary for ROM MBC
    pub fn read(self: *ROM,address: u16) u8{

        return switch (address) {
            0...0x7FFF => self.Data.*[address],
            0xA000...0xBFFF => self.RAM[address - 0xA000],
            else => 0xFF,
        };
    }

    pub fn write(self: *ROM,address : u16, data : u8) void {
        switch (address) {
            0...0x7FFF => self.Data.*[address] = data,
            0xA000...0xBFFF => self.RAM[address - 0xA000] = data,
            else => {},
        }
    }

    pub fn save(self: *ROM ,filePath : []const u8) !void{

        try saveFile(filePath, self.RAM[0..],".sav");
    }

    pub fn reloadSave(self: *ROM ,filePath : []const u8) !void{

        try reloadsaveFile(filePath, self.RAM[0..],".sav");
    }
};

const MBC1 = struct {

    HasRam : bool = false,
    HasBattery : bool = false,

    Data : *[]u8,
    Header : *Header,

    RAM : [0x8000]u8 = [_]u8{0} ** 0x8000,
    currentRamBank: u8 = 0,
    currentRomBank: u8 = 1,
    ZeroBank: u8 = 0,
    HighBank: u8 = 0,

    // Useful Flags
    modeFlag : bool = false,
    ramEnabled : bool = false,

    pub fn read(self: *MBC1,address: u16) u8{

        self.calculateBanks();

        return switch (address) {
            0...0x3FFF => if (!self.modeFlag) self.Data.*[address] else self.Data.*[@as(u32,address) + @as(u32,self.ZeroBank)*0x4000],
            0x4000...0x7FFF => self.Data.*[@as(u32,(address - 0x4000)) + @as(u32,self.HighBank) * 0x4000],
            0xA000...0xBFFF => blk :{
                if(!self.ramEnabled){ 
                    break :blk 0xFF;
                }
                
                if(self.Header.ram_size >= 0x03){
                    break :blk if(self.modeFlag) self.RAM[@as(u32,(address - 0xA000)) + @as(u32,self.currentRamBank) * 0x2000] else self.RAM[address - 0xA000];
                }
                else {
                    break :blk self.RAM[address - 0xA000];
                }
            },
            else => 0xFF,
        };
    }

    pub fn write(self: *MBC1,address : u16, data : u8) void {
        switch (address) {
            0...0x1FFF => self.ramEnabled = ((data & 0xF) == 0xA),
            0x2000...0x3FFF => {
                if(data == 0x00){
                    self.currentRomBank = 1; 
                    return;
                }

                self.currentRomBank = switch (self.Header.rom_size) {
                    0 => 1,
                    1 => data & 0x3,
                    2 => data & 0x7,
                    3 => data & 0xF,
                    4...6 => data & 0x1F,
                    else => 1,
                };
            },
            0x4000...0x5FFF => self.currentRamBank = (self.currentRamBank & 0xFC) | (data & 0x3),
            0x6000...0x7FFF => self.modeFlag = @bitCast(@as(u1,@truncate(data))),
            0xA000...0xBFFF => {
                if(!self.ramEnabled) return;

                if(self.Header.ram_size >= 0x3){
                    if(self.modeFlag){
                        self.RAM[@as(u32,(address - 0xA000)) + @as(u32,self.currentRamBank) * 0x2000] = data;
                    }else{
                        self.RAM[address - 0xA000] = data;
                    }
                }
                else{
                    self.RAM[(address - 0xA000) & 0x1FFF] = data;
                }
            },
            else => {},
        }
    }

    fn calculateBanks(self: *MBC1) void{
        switch (self.Header.rom_size) {
            0...4 => {
                self.HighBank = self.currentRomBank;  
                self.ZeroBank = 0;
            },
            5 => {
                self.HighBank = (self.currentRomBank & 0b11011111) | ((self.currentRamBank & 0x1) << 5);
                self.ZeroBank = (self.currentRamBank & 0x1) << 5;
            },
            6 => {
                self.HighBank = (self.currentRomBank & 0b10011111) | ((self.currentRamBank & 0x3) << 5);
                self.ZeroBank = (self.currentRamBank & 0x3) << 5;
            },
            else => self.HighBank = self.currentRomBank,
        }
    }

    pub fn save(self: *MBC1 ,filePath : []const u8) !void{

        try saveFile(filePath, self.RAM[0..],".sav");
    }

    pub fn reloadSave(self: *MBC1 ,filePath : []const u8) !void{

        try reloadsaveFile(filePath, self.RAM[0..],".sav");
    }
};

const MBC2 = struct {

    HasBattery : bool = false,
    Data : *[]u8,
    Header : *Header,

    RAM : [512]u8 = [_]u8{0} ** 512,
    currentRomBank: u8 = 1,
    currentRamBank: u8 = 0,

    ramEnabled : bool = false,

    pub fn read(self : *MBC2,address: u16) u8{
        return switch (address) {
            0x4000...0x7FFF => self.Data.*[@as(u32,(address-0x4000)) + @as(u32,self.currentRomBank) * 0x4000],
            0xA000...0xBFFF => blk:{
                if(!self.ramEnabled) break :blk 0xFF;
                break :blk 0xF0 | (self.RAM[(@as(u32,(address - 0xA000))&0x1FF) + @as(u16,self.currentRamBank) * 0x2000] & 0xF);
            },
            else => self.RAM[address],
        };
    }

    pub fn write(self : *MBC2,address : u16, data : u8) void {
        switch (address) {
            0...0x3FFF =>{
                if(((address >> 8) & 1) == 0){
                    self.ramEnabled = ((data&0xF) == 0xA);
                }
                else {
                    self.currentRomBank = if(data != 0) data & 0xF else 1;
                }
            },
            0xA000...0xBFFF => {
                if(!self.ramEnabled) return;
                self.RAM[(address-0xA000)&0x1FF] = data; // only half bytes are stored
            },
            else => {},
        }
        // discard since we dont need header data

    }

    pub fn save(self: *MBC2 ,filePath : []const u8) !void{

        try saveFile(filePath, self.RAM[0..],".sav");
    }

    pub fn reloadSave(self: *MBC2 ,filePath : []const u8) !void{

        try reloadsaveFile(filePath, self.RAM[0..],".sav");
    }
};

const MBC3 = struct {

    //necessary for access to the sub second ticks
    Emu : *GBC,

    HasRam : bool = false,
    HasBattery : bool = false,
    HasTimer : bool = false,

    Data : *[]u8,
    Header : *Header,

    RAM : [0x8000]u8 = [_]u8{0} ** 0x8000,
    currentRomBank : u8 = 1,
    currentRamBank : u8 = 0,
    currentRTCreg  : u8 = 0,

    ramEnabled: bool = false,
    ClockRegisterMapped: bool = false,
    latchOccured : bool = false,

    RTC : RTC_Regs = RTC_Regs{},
    RTCLatched : RTC_Regs = RTC_Regs{},

    prevInput: u8 = 0x10,

    const RTC_Regs = struct {
        s : u8 = 0,
        m : u8 = 0,
        h : u8 = 0,
        DL: u8 = 0,
        DH: u8 = 0,
    };

    pub fn read(self: *MBC3,address: u16) u8{
        return switch (address) {
            0...0x3FFF => self.Data.*[address],
            0x4000...0x7FFF => self.Data.*[@as(u32,(address-0x4000)) + @as(u32,self.currentRomBank) * 0x4000],
            0xA000...0xBFFF => blk:{
                if(self.ClockRegisterMapped){
                    if(!self.latchOccured) break :blk 0xFF;
                    break :blk switch (self.currentRTCreg) {
                        8 => 0b11000000 | self.RTCLatched.s,
                        9 => 0b11000000 | self.RTCLatched.m,
                        0xA => 0b11100000 | self.RTCLatched.h,
                        0xB => self.RTCLatched.DL,
                        0xC => 0b00111110 | self.RTCLatched.DH,
                        else => unreachable,
                    };
                }
                else {
                    if(!self.ramEnabled) break :blk 0xFF;
                    break :blk self.RAM[@as(u32,(address-0xA000)) + @as(u32,self.currentRamBank) * 0x2000];
                }
            },
            else => 0xFF,
        };
    }

    pub fn write(self: *MBC3,address : u16, data : u8) void {
        switch (address) {
            0...0x1FFF => self.ramEnabled = ((data&0xF) == 0xA),
            0x2000...0x3FFF => self.currentRomBank = if(data == 0) 1 else data & 0x7F,
            0x4000...0x5FFF =>{
                if(data <= 3){
                    self.ClockRegisterMapped = false;
                    self.currentRamBank = data;
                }
                else if(data >= 0x08 and data <= 0x0C) {
                    self.ClockRegisterMapped = true;
                    self.currentRTCreg = data;
                }
            },
            0x6000...0x7FFF =>{
                if(self.prevInput == 0 and data == 1){
                    self.RTCLatched = self.RTC;
                    self.latchOccured = true;
                }
                self.prevInput = data;
            },
            0xA000...0xBFFF =>{
                if(self.ClockRegisterMapped){
                    switch (self.currentRTCreg) {
                        0x08 => {
                            self.RTCLatched.s = data & 0b00111111;
                            self.RTC.s = data & 0b00111111;
                            self.Emu.ticks = 0; // resets sub second counter 
                        },
                        0x09 => {
                            self.RTCLatched.m = data & 0b00111111;
                            self.RTC.m = data & 0b00111111;
                        },
                        0x0A => {
                            self.RTCLatched.h = data & 0b00011111;
                            self.RTC.h = data & 0b00011111;
                        },
                        0x0B => {
                            self.RTCLatched.DL = data;
                            self.RTC.DL = data;
                        },
                        0x0C => {
                            self.RTCLatched.DH = data & 0b11000001;
                            self.RTC.DH = data & 0b11000001;
                        },
                        else => {},
                    }
                }
                else{
                    if(!self.ramEnabled) return;
                    self.RAM[@as(u32,(address-0xA000)) + @as(u32,self.currentRamBank) * 0x2000] = data;
                }
            },
            else => {},
        }
    }

    pub fn save(self: *MBC3 ,filePath : []const u8) !void{

        try saveFile(filePath, self.RAM[0..],".sav");
        if(self.HasTimer) try saveFile(filePath, std.mem.asBytes(&self.RTCLatched),".rtc");
    }

    pub fn reloadSave(self: *MBC3 ,filePath : []const u8) !void{

        try reloadsaveFile(filePath, self.RAM[0..],".sav");
        if(self.HasTimer) try reloadsaveFile(filePath, std.mem.asBytes(&self.RTCLatched),".rtc");
        self.RTC = self.RTCLatched;
    }

    pub fn tick(self : *MBC3) void{

        self.RTC.s +%= 1;
        if(self.RTC.s == 60)
        {
            self.RTC.s = 0;
            self.RTC.m+%=1;
            if(self.RTC.m == 60)
            {
                self.RTC.m = 0;
                self.RTC.h+%=1;
                if(self.RTC.h == 24)
                {
                    self.RTC.DL+%=1;
                    self.RTC.h = 0;
            
                    if(self.RTC.DL == 0x00)
                    {
                        self.RTC.DH ^= (1<<7);
                    }
                }
            }
        }
    }
};

const MBC5 = struct {

    HasRam : bool = false,
    HasBattery : bool = false,
    HasRumble : bool = false,

    Data : *[]u8,
    Header : *Header,

    RAM : [0x20000]u8 = [_]u8{0} ** 0x20000,
    currentRamBank: u8 = 0,
    currentRomBank: u16 = 0,

    ramEnabled : bool = false,

    pub fn read(self: *MBC5,address: u16) u8{

        return switch (address) {
            0...0x3FFF => self.Data.*[address],
            0x4000...0x7FFF => self.Data.*[@as(u32,(address - 0x4000)) + @as(u32,self.currentRomBank) * 0x4000],
            0xA000...0xBFFF => blk :{
                if(!self.ramEnabled) break :blk 0xFF;
                
                break :blk self.RAM[@as(u32,(address - 0xA000)) + (@as(u32,self.currentRamBank) * 0x2000)];

            },
            else => 0xFF,
        };
    }

    pub fn write(self: *MBC5,address : u16, data : u8) void {
        switch (address) {
            0...0x1FFF => self.ramEnabled = ((data&0xF) == 0xA),
            0x2000...0x2FFF => self.currentRomBank = self.currentRomBank&0xFF00 | @as(u16,data), // bottom 8 bits of RomBank
            0x3000...0x3FFF => self.currentRomBank = (self.currentRomBank&0xFF) | (@as(u16,data&1) << 8), // 9th bit
            0x4000...0x5FFF => self.currentRamBank = data,
            0xA000...0xBFFF => {
                if(!self.ramEnabled) return;
                self.RAM[@as(u32,(address - 0xA000)) + (@as(u32,self.currentRamBank) * 0x2000)] = data;
            },
            else => {},
        }
    }

    pub fn save(self: *MBC5 ,filePath : []const u8) !void{

        try saveFile(filePath, self.RAM[0..],".sav");
    }

    pub fn reloadSave(self: *MBC5 ,filePath : []const u8) !void{

        try reloadsaveFile(filePath, self.RAM[0..],".sav");
    }

};

fn saveFile(filePath: []const u8, ramSlice : []u8, extension: []const u8) !void{

    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const saveFilePath = try changeFileType(allocator,filePath, extension);
    defer allocator.free(saveFilePath);

    var file = std.fs.cwd().createFile(saveFilePath,.{.read = true})

    // if save file alread exists open that instead
    catch |err| switch (err) {
        error.PathAlreadyExists => try std.fs.cwd().openFile(saveFilePath, .{ .mode = .read_write }),
        else => unreachable,
    }; 

    defer file.close();

    try file.seekTo(0);
    _ = try file.writeAll(ramSlice);
}

fn reloadsaveFile(filePath: []const u8, ramSlice : []u8, extension : []const u8) !void{

    var buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    const saveFilePath = try changeFileType(allocator,filePath,extension);
    defer allocator.free(saveFilePath);

    var file = try std.fs.cwd().openFile(saveFilePath, .{ .mode = .read_write });

    defer file.close();

    try file.seekTo(0);
    _ = try file.readAll(ramSlice);
}



