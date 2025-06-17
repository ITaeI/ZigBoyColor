const std = @import("std");
const GBC = @import("GBC.zig").GBC;


pub const SM83 = struct {

    regs : Registers,
    Emu  : *GBC,

    pub fn init(parentPtr : *GBC) SM83{

        return SM83{
            .regs = Registers.init(),
            .Emu = parentPtr,
        };
    }

    pub fn step(self : *SM83) void{

        // Fetch Opcode

        // CB instruction

        // Regular instruction

        // possible interrupt

        _ = self;

    }
};

const Registers = struct {

    af : FlagRegister = undefined,
    bc : DualRegister = undefined,
    de : DualRegister = undefined,
    hl : DualRegister = undefined,
    pc : u16 = 0x100,  // always starts at 0x100
    sp : u16 = 0xFFFE, // always starts at 0xFFFE

    pub fn SetFlag(self: *Registers, flag: Flag, b: bool) void{
        switch (flag) {
            .C => self.af.flags.C = b,
            .H => self.af.flags.H = b,
            .N => self.af.flags.N = b,
            .Z => self.af.flags.Z = b,
        }
    }

    pub fn CheckFlag(self: *Registers, flag: Flag) bool{
        return switch (flag) {
            .C => self.af.flags.C,
            .H => self.af.flags.H,
            .N => self.af.flags.N,
            .Z => self.af.flags.Z,
        };
    }

    pub fn init() Registers{
        var r = Registers{};
        // Lets set initial the values
        r.af.setFlagByte(0x80);
        r.af.a.set(0x11);

        r.bc.set(0x0);
        r.de.set(0xFF58);
        r.hl.set(0x000D);

        // TODO: Check whether we are running in DMG or CGB mode

        return r;
    }
};

pub const Register8Bit = struct {
    value : u8 = undefined,

    pub fn get(self:*Register8Bit) u8{
        return self.value;
    }

    pub fn set(self:*Register8Bit,v:u8)void{
        self.value = v;
    }

    pub fn Inc(self:*Register8Bit)void{
        self.value +%= 1;
    }

    pub fn Dec(self:*Register8Bit)void{
        self.value -%= 1;
    }
};

const DualRegister = struct {
    lo : Register8Bit,
    hi : Register8Bit,

    pub fn get(self: *DualRegister) u16{
        return @as(u16,(self.hi.get() << 8) | self.lo.get());
    }

    pub fn set(self: *DualRegister, v: u16) void {
        self.lo.set(@truncate(v));
        self.hi.set(@truncate(v >> 8));
    } 

    pub fn Inc(self: *DualRegister)void{
        self.set(self.get() +% 1);
    }

    pub fn Dec(self: *DualRegister)void{
        self.set(self.get() -% 1);
    }
};

const FlagRegister = struct {
    flags: flagFormat,
    a : Register8Bit,

    const flagFormat = packed struct {
        padding : u4 = 0x0,
        C : bool = false,
        H : bool = false,
        N : bool = false,
        Z : bool = false,
    };

    pub fn getFlagByte(self: *FlagRegister)u8{
        return @bitCast(self.flags);
    }

    pub fn setFlagByte(self: *FlagRegister,v:u8)void{
        self.flags = @bitCast(v);
    }
};

const Flag = enum {
    C,
    H,
    N,
    Z,
};



