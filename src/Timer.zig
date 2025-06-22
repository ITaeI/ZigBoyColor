const std = @import("std");
const DualRegister = @import("SM83.zig").DualRegister;
const Register8Bit = @import("SM83.zig").Register8Bit;
const GBC = @import("GBC.zig").GBC;

pub const Timer = struct {

    Emu : *GBC,
    DIV : DualRegister = undefined,
    TIMA : Register8Bit = undefined,
    TMA : Register8Bit = undefined,
    TAC : Register8Bit = undefined,

    var TimaOverflowOccured: bool = false;
    var OverflowCounter : u8 = 0;

    pub fn init(parentPtr : *GBC)Timer{

        var T = Timer{
            .Emu = parentPtr
        };
        T.DIV.set(0xABCC);
        T.TIMA.set(0x00);
        T.TMA.set(0x00);
        T.TAC.set(0xF8);

        return T;
    }

    pub fn tick(self : *Timer) void{

        const DivPrev : u16 = self.DIV.get();
        self.DIV.Inc();
        var FallingEdge : bool = false;

        if(self.DIV.hi.getBit(4) != 1 and DivPrev >> 12 != 0){
            // Apu Count
        } 

        if(TimaOverflowOccured){
            OverflowCounter += 1;
        }

        // Bit 2 determines if timer is on
        if(self.TAC.getBit(2) == 1){

            FallingEdge = switch (@as(u2,@truncate(self.TAC.get()))) {
                0b00 => self.DIV.hi.getBit(1) != 1 and ((DivPrev >> 9) & 1) != 0,
                0b01 => self.DIV.lo.getBit(3) != 1 and ((DivPrev >> 3) & 1) != 0,
                0b10 => self.DIV.lo.getBit(5) != 1 and ((DivPrev >> 5) & 1) != 0,
                0b11 => self.DIV.lo.getBit(7) != 1 and ((DivPrev >> 7) & 1) != 0,
            };

            if(FallingEdge){
                self.TIMA.Inc();
                if(self.TIMA.get() == 0x00){
                    TimaOverflowOccured =true;
                }
            }
        }

        if(TimaOverflowOccured and OverflowCounter == 4){
                OverflowCounter = 0;
                TimaOverflowOccured = false;
                self.TIMA.set(self.TMA.get());

                // Request Timer interrupt (bit 2)
                self.Emu.cpu.regs.IF.setBit(2, 1);
        }


    }

    pub fn read(self : *Timer, address : u16)u8{

        return switch (address) {
            0xFF04 => self.DIV.hi.get(),
            0xFF05 => self.TIMA.get(),
            0xFF06 => self.TMA.get(),
            0xFF07 => self.TAC.get() & 7,
            else => 0xFF,
        };
    }
    pub fn write(self : *Timer, address : u16,data : u8)void{
        switch (address) {
            0xFF04 => self.DIV.set(0),
            0xFF05 => self.TIMA.set(data),
            0xFF06 => self.TMA.set(data),
            0xFF07 => self.TAC.set((self.TAC.get() & 0xFC) | (data & 7)),
            else => {},
        }
    }
};