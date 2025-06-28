const std = @import("std");
const GBC = @import("GBC.zig").GBC;


pub const SM83 = struct {

    Emu  : *GBC,
    regs : Registers,
    OpcodeTable : [256]Instruction = undefined,
    OpcodeTableCB : [256]Instruction = undefined,

    IME: bool = false,
    IMEWait : bool = false,
    IMEWaitCount : u8 = 0,
    isHalted : bool = false,
    HaltBug : bool = false,

    dmaWasActive: bool = false,

    pub fn init(parentPtr : *GBC) SM83{

        return SM83{
            .regs = Registers.init(parentPtr),
            .Emu = parentPtr,
        };
    }

    pub fn step(self : *SM83) void{

        if(!self.isHalted){

            // Fetch Opcode
            var opcode : u8 = self.readMem(self.regs.pc);
            
            // Halt bug causes pc to not increment
            if(self.HaltBug){
                self.regs.pc -%= 1;
                self.HaltBug = false;
            }

            // Execute instruction
            if(opcode == 0xCB) 
            {
                opcode = self.readMem(self.regs.pc);
                const i = self.OpcodeTableCB[opcode];
                i.handler(self, i.Op1, i.Op2);

                
            }
            else {


                const i = self.OpcodeTable[opcode];
                // std.debug.print("Mnemonic {s}\n", .{i.mnemonic});
                // std.debug.print("PC : {x}\n", .{self.regs.pc});
                i.handler(self, i.Op1, i.Op2); 


            }
        }
        else{
            self.Emu.cycle();
            if((self.regs.IE.get() & self.regs.IF.get()) != 0){
                self.isHalted = false;


                self.Emu.dma.VRAMTransferInProgress = self.dmaWasActive;
                self.dmaWasActive = false;
            }
        }

        // possible interrupt

        // so the IME is set one instruction after
        if(self.IMEWait){ 
            self.IMEWaitCount += 1;
            if(self.IMEWaitCount == 2){
                self.IME = true;
                self.IMEWait = false;
                self.IMEWaitCount = 0;
            }
        }

        // Then we call the interrupt handler if Ime is true
        if(self.IME){
            // call interrupt here
            self.InterruptHandler();
        }

    }

    fn InterruptHandler(self: *SM83) void{

        var IntVector: u16 = 0x40;
        // check leading zeros to find which interrupt to service
        const zct: u3 = @truncate(@ctz(self.regs.IE.get()));
        if(zct < 5){

            if(self.regs.IE.getBit(zct) == 1 and self.regs.IF.getBit(zct) == 1 ){
                
                self.Emu.cycle();
                self.Emu.cycle();

                // 2 cycles pushing PC to stack

                self.regs.sp.Dec();
                self.writeMem(self.regs.sp.get(), @truncate(self.regs.pc >> 8));
                self.regs.sp.Dec();
                self.writeMem(self.regs.sp.get(), @truncate(self.regs.pc));
                
                // 1 last cycle setting new PC value
                IntVector += (8 * @as(u16,zct));
                self.regs.pc = IntVector;
                self.Emu.cycle();

                // reset ime flag
                self.IME = false;
                // reset IF flag
                self.regs.IF.setBit(zct, 0);

            }
        }
    }

    pub fn fetch16bits(self: *SM83) u16 {
        const lo = self.readMem(self.regs.pc);
        const hi = self.readMem(self.regs.pc);
        return buildAddress(lo, hi);
    }

    pub fn readMem(self: *SM83,address:u16)u8{

        const mem : u8 = self.Emu.bus.read(address);
        if (address == self.regs.pc)
        {
            self.regs.pc +%= 1;
        }
        self.Emu.cycle();
        return mem;
    }

    pub fn writeMem(self: *SM83,address:u16,data:u8)void{
        self.Emu.bus.write(address, data);
        self.Emu.cycle();
    }

    pub fn setupOpcodeTables(c: *SM83)void{

        c.OpcodeTable = [_]Instruction{
            .{ .handler = NOP, .mnemonic = "NOP" },
            .{ .handler = LD_R16_u16, .mnemonic = "LD BC, U16", .Op1 = Op{ .r16 = &c.regs.bc } },
            .{ .handler = LD_BC_A, .mnemonic = "LD (BC), A" },
            .{ .handler = INC_R16, .mnemonic = "INC BC", .Op1 = Op{ .r16 = &c.regs.bc } },
            .{ .handler = INC_R8, .mnemonic = "INC B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = DEC_R8, .mnemonic = "DEC B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_u8, .mnemonic = "LD B, u8", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = RLCA, .mnemonic = "RLCA" },
            .{ .handler = LD_u16_SP, .mnemonic = "LD (u16), SP" },
            .{ .handler = ADD_HL_R16, .mnemonic = "ADD HL, BC", .Op1 = Op{ .r16 = &c.regs.bc } },
            .{ .handler = LD_A_BC, .mnemonic = "LD A, (BC)" },
            .{ .handler = DEC_R16, .mnemonic = "DEC BC", .Op1 = Op{ .r16 = &c.regs.bc } },
            .{ .handler = INC_R8, .mnemonic = "INC C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = DEC_R8, .mnemonic = "DEC C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_u8, .mnemonic = "LD C, u8", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = RRCA, .mnemonic = "RRCA" },
            .{ .handler = STOP, .mnemonic = "STOP" },
            .{ .handler = LD_R16_u16, .mnemonic = "LD DE, u16", .Op1 = Op{ .r16 = &c.regs.de } },
            .{ .handler = LD_DE_A, .mnemonic = "LD (DE), A" },
            .{ .handler = INC_R16, .mnemonic = "INC DE", .Op1 = Op{ .r16 = &c.regs.de } },
            .{ .handler = INC_R8, .mnemonic = "INC D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = DEC_R8, .mnemonic = "DEC D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_u8, .mnemonic = "LD D, u8", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = RLA, .mnemonic = "RLA" },
            .{ .handler = JR_E, .mnemonic = "JR e" },
            .{ .handler = ADD_HL_R16, .mnemonic = "ADD HL, DE", .Op1 = Op{ .r16 = &c.regs.de } },
            .{ .handler = LD_A_DE, .mnemonic = "LD A, (DE)" },
            .{ .handler = DEC_R16, .mnemonic = "DEC DE", .Op1 = Op{ .r16 = &c.regs.de } },
            .{ .handler = INC_R8, .mnemonic = "INC E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = DEC_R8, .mnemonic = "DEC E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_u8, .mnemonic = "LD E, u8", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = RRA, .mnemonic = "RRA" },
            .{ .handler = JR_CC_E, .mnemonic = "JR NZ, e", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = false }} },
            .{ .handler = LD_R16_u16, .mnemonic = "LD HL, u16", .Op1 = Op{ .r16 = &c.regs.hl } },
            .{ .handler = LD_HL_INC_A, .mnemonic = "LD (HL+), A" },
            .{ .handler = INC_R16, .mnemonic = "INC HL", .Op1 = Op{ .r16 = &c.regs.hl } },
            .{ .handler = INC_R8, .mnemonic = "INC H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = DEC_R8, .mnemonic = "DEC H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_u8, .mnemonic = "LD H, u8", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = DAA, .mnemonic = "DAA" },
            .{ .handler = JR_CC_E, .mnemonic = "JR Z, e", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = true }} },
            .{ .handler = ADD_HL_R16, .mnemonic = "ADD HL, HL", .Op1 = Op{ .r16 = &c.regs.hl } },
            .{ .handler = LD_A_HL_INC, .mnemonic = "LD A, (HL+)" },
            .{ .handler = DEC_R16, .mnemonic = "DEC HL", .Op1 = Op{ .r16 = &c.regs.hl } },
            .{ .handler = INC_R8, .mnemonic = "INC L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = DEC_R8, .mnemonic = "DEC L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_u8, .mnemonic = "LD L, u8", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = CPL, .mnemonic = "CPL" },
            .{ .handler = JR_CC_E, .mnemonic = "JR NC, e", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = false }} },
            .{ .handler = LD_R16_u16, .mnemonic = "LD SP, u16", .Op1 = Op{ .r16 = &c.regs.sp } }, 
            .{ .handler = LD_HL_DEC_A, .mnemonic = "LD (HL-), A" },
            .{ .handler = INC_R16, .mnemonic = "INC SP", .Op1 = Op{ .r16 = &c.regs.sp } },
            .{ .handler = INC_HL, .mnemonic = "INC (HL)" },
            .{ .handler = DEC_HL, .mnemonic = "DEC (HL)" },
            .{ .handler = LD_HL_u8, .mnemonic = "LD (HL), u8" },
            .{ .handler = SCF, .mnemonic = "SCF" },
            .{ .handler = JR_CC_E, .mnemonic = "JR C, e", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = true }} },
            .{ .handler = ADD_HL_R16, .mnemonic = "ADD HL, SP", .Op1 = Op{ .r16 = &c.regs.sp } },
            .{ .handler = LD_A_HL_DEC, .mnemonic = "LD A, (HL-)" },
            .{ .handler = DEC_R16, .mnemonic = "DEC SP", .Op1 = Op{ .r16 = &c.regs.sp } },
            .{ .handler = INC_R8, .mnemonic = "INC A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = DEC_R8, .mnemonic = "DEC A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_u8, .mnemonic = "LD A, u8", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = CCF, .mnemonic = "CCF" },
            .{ .handler = LD_R8_R8, .mnemonic = "LD B, B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD B, C", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD B, D", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD B, E", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD B, H", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD B, L", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_HL, .mnemonic = "LD B, (HL)", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD B, A", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD C, B", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD C, C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD C, D", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD C, E", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD C, H", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD C, L", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_HL, .mnemonic = "LD C, (HL)", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD C, A", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD D, B", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD D, C", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD D, D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD D, E", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD D, H", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD D, L", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_HL, .mnemonic = "LD D, (HL)", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD D, A", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD E, B", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD E, C", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD E, D", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD E, E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD E, H", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD E, L", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_HL, .mnemonic = "LD E, (HL)", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD E, A", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD H, B", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD H, C", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD H, D", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD H, E", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD H, H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD H, L", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_HL, .mnemonic = "LD H, (HL)", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD H, A", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD L, B", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD L, C", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD L, D", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD L, E", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD L, H", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD L, L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_HL, .mnemonic = "LD L, (HL)", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD L, A", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_HL_R8, .mnemonic = "LD (HL), B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_HL_R8, .mnemonic = "LD (HL), C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_HL_R8, .mnemonic = "LD (HL), D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_HL_R8, .mnemonic = "LD (HL), E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_HL_R8, .mnemonic = "LD (HL), H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_HL_R8, .mnemonic = "LD (HL), L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = HALT, .mnemonic = "HALT" },
            .{ .handler = LD_HL_R8, .mnemonic = "LD (HL), A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD A, B", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD A, C", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD A, D", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD A, E", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD A, H", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD A, L", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = LD_R8_HL, .mnemonic = "LD A, (HL)", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = LD_R8_R8, .mnemonic = "LD A, A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = ADD_R8, .mnemonic = "ADD A, B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = ADD_R8, .mnemonic = "ADD A, C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = ADD_R8, .mnemonic = "ADD A, D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = ADD_R8, .mnemonic = "ADD A, E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = ADD_R8, .mnemonic = "ADD A, H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = ADD_R8, .mnemonic = "ADD A, L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = ADD_HL, .mnemonic = "ADD A, (HL)" },
            .{ .handler = ADD_R8, .mnemonic = "ADD A, A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = ADC_R8, .mnemonic = "ADC A, B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = ADC_R8, .mnemonic = "ADC A, C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = ADC_R8, .mnemonic = "ADC A, D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = ADC_R8, .mnemonic = "ADC A, E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = ADC_R8, .mnemonic = "ADC A, H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = ADC_R8, .mnemonic = "ADC A, L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = ADC_HL, .mnemonic = "ADC A, (HL)" },
            .{ .handler = ADC_R8, .mnemonic = "ADC A, A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = SUB_R8, .mnemonic = "SUB B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = SUB_R8, .mnemonic = "SUB C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = SUB_R8, .mnemonic = "SUB D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = SUB_R8, .mnemonic = "SUB E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = SUB_R8, .mnemonic = "SUB H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = SUB_R8, .mnemonic = "SUB L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = SUB_HL, .mnemonic = "SUB (HL)" },
            .{ .handler = SUB_R8, .mnemonic = "SUB A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = SBC_R8, .mnemonic = "SBC A, B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = SBC_R8, .mnemonic = "SBC A, C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = SBC_R8, .mnemonic = "SBC A, D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = SBC_R8, .mnemonic = "SBC A, E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = SBC_R8, .mnemonic = "SBC A, H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = SBC_R8, .mnemonic = "SBC A, L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = SBC_HL, .mnemonic = "SBC A, (HL)" },
            .{ .handler = SBC_R8, .mnemonic = "SBC A, A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = AND_R8, .mnemonic = "AND B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = AND_R8, .mnemonic = "AND C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = AND_R8, .mnemonic = "AND D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = AND_R8, .mnemonic = "AND E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = AND_R8, .mnemonic = "AND H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = AND_R8, .mnemonic = "AND L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = AND_HL, .mnemonic = "AND (HL)" },
            .{ .handler = AND_R8, .mnemonic = "AND A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = XOR_R8, .mnemonic = "XOR B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = XOR_R8, .mnemonic = "XOR C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = XOR_R8, .mnemonic = "XOR D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = XOR_R8, .mnemonic = "XOR E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = XOR_R8, .mnemonic = "XOR H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = XOR_R8, .mnemonic = "XOR L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = XOR_HL, .mnemonic = "XOR (HL)" },
            .{ .handler = XOR_R8, .mnemonic = "XOR A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = OR_R8, .mnemonic = "OR B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = OR_R8, .mnemonic = "OR C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = OR_R8, .mnemonic = "OR D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = OR_R8, .mnemonic = "OR E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = OR_R8, .mnemonic = "OR H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = OR_R8, .mnemonic = "OR L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = OR_HL, .mnemonic = "OR (HL)" },
            .{ .handler = OR_R8, .mnemonic = "OR A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = CP_R8, .mnemonic = "CP B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = CP_R8, .mnemonic = "CP C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = CP_R8, .mnemonic = "CP D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = CP_R8, .mnemonic = "CP E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = CP_R8, .mnemonic = "CP H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = CP_R8, .mnemonic = "CP L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = CP_HL, .mnemonic = "CP (HL)" },
            .{ .handler = CP_R8, .mnemonic = "CP A", .Op1 = Op{ .r8 = &c.regs.af.a } },
            .{ .handler = RET_CC, .mnemonic = "RET NZ", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = false }} },
            .{ .handler = POP_R16, .mnemonic = "POP BC", .Op1 = Op{ .r16 = &c.regs.bc } },
            .{ .handler = JP_CC_u16, .mnemonic = "JP NZ, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = false }} },
            .{ .handler = JP_u16, .mnemonic = "JP u16" },
            .{ .handler = CALL_CC_u16, .mnemonic = "CALL NZ, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = false }} },
            .{ .handler = PUSH_R16, .mnemonic = "PUSH BC", .Op1 = Op{ .r16 = &c.regs.bc } },
            .{ .handler = ADD_u8, .mnemonic = "ADD A, u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 00H", .Op1 = Op{ .bit = 0x00 } },
            .{ .handler = RET_CC, .mnemonic = "RET Z", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = true }} },
            .{ .handler = RET, .mnemonic = "RET" },
            .{ .handler = JP_CC_u16, .mnemonic = "JP Z, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = true }} },
            .{ .handler = NOP, .mnemonic = "PREFIX CB" }, // 0xCB
            .{ .handler = CALL_CC_u16, .mnemonic = "CALL Z, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.Z, .state = true }} },
            .{ .handler = CALL_u16, .mnemonic = "CALL u16" },
            .{ .handler = ADC_u8, .mnemonic = "ADC A, u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 08H", .Op1 = Op{ .bit = 0x08 } },
            .{ .handler = RET_CC, .mnemonic = "RET NC", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = false }} },
            .{ .handler = POP_R16, .mnemonic = "POP DE", .Op1 = Op{ .r16 = &c.regs.de } },
            .{ .handler = JP_CC_u16, .mnemonic = "JP NC, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = false }} },
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xD3 (unofficial/unused)
            .{ .handler = CALL_CC_u16, .mnemonic = "CALL NC, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = false }} },
            .{ .handler = PUSH_R16, .mnemonic = "PUSH DE", .Op1 = Op{ .r16 = &c.regs.de } },
            .{ .handler = SUB_u8, .mnemonic = "SUB u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 10H", .Op1 = Op{ .bit = 0x10 } },
            .{ .handler = RET_CC, .mnemonic = "RET C", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = true }} },
            .{ .handler = RETI, .mnemonic = "RETI" },
            .{ .handler = JP_CC_u16, .mnemonic = "JP C, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = true }} },
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xDB (unofficial/unused)
            .{ .handler = CALL_CC_u16, .mnemonic = "CALL C, u16", .Op1 = Op{ .flag = .{.type = StatusFlag.C, .state = true }} },
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xDD (unofficial/unused)
            .{ .handler = SBC_u8, .mnemonic = "SBC A, u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 18H", .Op1 = Op{ .bit = 0x18 } },
            .{ .handler = LDH_u8_A, .mnemonic = "LDH (u8), A" },
            .{ .handler = POP_R16, .mnemonic = "POP HL", .Op1 = Op{ .r16 = &c.regs.hl } },
            .{ .handler = LDH_C_A, .mnemonic = "LDH (C), A" },
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xE3 (unofficial/unused)
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xE4 (unofficial/unused)
            .{ .handler = PUSH_R16, .mnemonic = "PUSH HL", .Op1 = Op{ .r16 = &c.regs.hl } },
            .{ .handler = AND_u8, .mnemonic = "AND u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 20H", .Op1 = Op{ .bit = 0x20 } },
            .{ .handler = ADD_SP_E, .mnemonic = "ADD SP, e" },
            .{ .handler = JP_HL, .mnemonic = "JP (HL)" },
            .{ .handler = LD_u16_A, .mnemonic = "LD (u16), A" },
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xEB (unofficial/unused)
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xEC (unofficial/unused)
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xED (unofficial/unused)
            .{ .handler = XOR_u8, .mnemonic = "XOR u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 28H", .Op1 = Op{ .bit = 0x28 } },
            .{ .handler = LDH_A_u8, .mnemonic = "LDH A, (u8)" },
            .{ .handler = POP_AF, .mnemonic = "POP AF" },
            .{ .handler = LDH_A_C, .mnemonic = "LDH A, (C)" },
            .{ .handler = DI, .mnemonic = "DI" },
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xF4 (unofficial/unused)
            .{ .handler = PUSH_AF, .mnemonic = "PUSH AF" },
            .{ .handler = OR_u8, .mnemonic = "OR u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 30H", .Op1 = Op{ .bit = 0x30 } },
            .{ .handler = LD_HL_SP_E, .mnemonic = "LD HL, SP+e" },
            .{ .handler = LD_SP_HL, .mnemonic = "LD SP, HL" },
            .{ .handler = LD_A_u16, .mnemonic = "LD A, (u16)" },
            .{ .handler = EI, .mnemonic = "EI" },
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xFC (unofficial/unused)
            .{ .handler = NOP, .mnemonic = "NOP" }, // 0xFD (unofficial/unused)
            .{ .handler = CP_u8, .mnemonic = "CP u8" },
            .{ .handler = RST_u8, .mnemonic = "RST 38H", .Op1 = Op{ .bit = 0x38 } },
        };
        
        c.OpcodeTableCB = [_]Instruction{
            // 0x00 - 0x07: RLC r
            .{ .handler = RLC_R8, .mnemonic = "RLC B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = RLC_R8, .mnemonic = "RLC C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = RLC_R8, .mnemonic = "RLC D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = RLC_R8, .mnemonic = "RLC E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = RLC_R8, .mnemonic = "RLC H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = RLC_R8, .mnemonic = "RLC L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = RLC_HL, .mnemonic = "RLC (HL)" },
            .{ .handler = RLC_R8, .mnemonic = "RLC A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x08 - 0x0F: RRC r
            .{ .handler = RRC_R8, .mnemonic = "RRC B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = RRC_R8, .mnemonic = "RRC C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = RRC_R8, .mnemonic = "RRC D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = RRC_R8, .mnemonic = "RRC E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = RRC_R8, .mnemonic = "RRC H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = RRC_R8, .mnemonic = "RRC L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = RRC_HL, .mnemonic = "RRC (HL)" },
            .{ .handler = RRC_R8, .mnemonic = "RRC A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x10 - 0x17: RL r
            .{ .handler = RL_R8, .mnemonic = "RL B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = RL_R8, .mnemonic = "RL C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = RL_R8, .mnemonic = "RL D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = RL_R8, .mnemonic = "RL E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = RL_R8, .mnemonic = "RL H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = RL_R8, .mnemonic = "RL L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = RL_HL, .mnemonic = "RL (HL)" },
            .{ .handler = RL_R8, .mnemonic = "RL A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x18 - 0x1F: RR r
            .{ .handler = RR_R8, .mnemonic = "RR B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = RR_R8, .mnemonic = "RR C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = RR_R8, .mnemonic = "RR D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = RR_R8, .mnemonic = "RR E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = RR_R8, .mnemonic = "RR H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = RR_R8, .mnemonic = "RR L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = RR_HL, .mnemonic = "RR (HL)" },
            .{ .handler = RR_R8, .mnemonic = "RR A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x20 - 0x27: SLA r
            .{ .handler = SLA_R8, .mnemonic = "SLA B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = SLA_R8, .mnemonic = "SLA C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = SLA_R8, .mnemonic = "SLA D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = SLA_R8, .mnemonic = "SLA E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = SLA_R8, .mnemonic = "SLA H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = SLA_R8, .mnemonic = "SLA L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = SLA_HL, .mnemonic = "SLA (HL)" },
            .{ .handler = SLA_R8, .mnemonic = "SLA A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x28 - 0x2F: SRA r
            .{ .handler = SRA_R8, .mnemonic = "SRA B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = SRA_R8, .mnemonic = "SRA C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = SRA_R8, .mnemonic = "SRA D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = SRA_R8, .mnemonic = "SRA E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = SRA_R8, .mnemonic = "SRA H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = SRA_R8, .mnemonic = "SRA L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = SRA_HL, .mnemonic = "SRA (HL)" },
            .{ .handler = SRA_R8, .mnemonic = "SRA A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x30 - 0x37: SWAP r
            .{ .handler = SWAP_R8, .mnemonic = "SWAP B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = SWAP_R8, .mnemonic = "SWAP C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = SWAP_R8, .mnemonic = "SWAP D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = SWAP_R8, .mnemonic = "SWAP E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = SWAP_R8, .mnemonic = "SWAP H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = SWAP_R8, .mnemonic = "SWAP L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = SWAP_HL, .mnemonic = "SWAP (HL)" },
            .{ .handler = SWAP_R8, .mnemonic = "SWAP A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x38 - 0x3F: SRL r
            .{ .handler = SRL_R8, .mnemonic = "SRL B", .Op1 = Op{ .r8 = &c.regs.bc.hi } },
            .{ .handler = SRL_R8, .mnemonic = "SRL C", .Op1 = Op{ .r8 = &c.regs.bc.lo } },
            .{ .handler = SRL_R8, .mnemonic = "SRL D", .Op1 = Op{ .r8 = &c.regs.de.hi } },
            .{ .handler = SRL_R8, .mnemonic = "SRL E", .Op1 = Op{ .r8 = &c.regs.de.lo } },
            .{ .handler = SRL_R8, .mnemonic = "SRL H", .Op1 = Op{ .r8 = &c.regs.hl.hi } },
            .{ .handler = SRL_R8, .mnemonic = "SRL L", .Op1 = Op{ .r8 = &c.regs.hl.lo } },
            .{ .handler = SRL_HL, .mnemonic = "SRL (HL)" },
            .{ .handler = SRL_R8, .mnemonic = "SRL A", .Op1 = Op{ .r8 = &c.regs.af.a } },

            // 0x40 - 0x47: BIT 0, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 0,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 0,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 0,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 0,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 0,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 0,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 0,(HL)", .Op1 = Op{ .bit = 0 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 0,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 0 } },

            // 0x48 - 0x4F: BIT 1, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 1,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 1,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 1,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 1,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 1,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 1,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 1,(HL)", .Op1 = Op{ .bit = 1 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 1,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 1 } },

            // 0x50 - 0x57: BIT 2, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 2,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 2,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 2,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 2,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 2,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 2,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 2,(HL)", .Op1 = Op{ .bit = 2 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 2,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 2 } },

            // 0x58 - 0x5F: BIT 3, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 3,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 3,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 3,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 3,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 3,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 3,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 3,(HL)", .Op1 = Op{ .bit = 3 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 3,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 3 } },

            // 0x60 - 0x67: BIT 4, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 4,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 4,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 4,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 4,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 4,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 4,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 4,(HL)", .Op1 = Op{ .bit = 4 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 4,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 4 } },

            // 0x68 - 0x6F: BIT 5, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 5,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 5,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 5,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 5,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 5,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 5,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 5,(HL)", .Op1 = Op{ .bit = 5 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 5,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 5 } },

            // 0x70 - 0x77: BIT 6, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 6,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 6,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 6,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 6,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 6,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 6,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 6,(HL)", .Op1 = Op{ .bit = 6 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 6,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 6 } },

            // 0x78 - 0x7F: BIT 7, r
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 7,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 7,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 7,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 7,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 7,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 7,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = BIT_B_HL, .mnemonic = "BIT 7,(HL)", .Op1 = Op{ .bit = 7 } },
            .{ .handler = BIT_B_R8, .mnemonic = "BIT 7,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 7 } },

            // 0x80 - 0x87: RES 0, r
            .{ .handler = RES_B_R8, .mnemonic = "RES 0,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 0,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 0,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 0,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 0,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 0,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 0,(HL)", .Op1 = Op{ .bit = 0 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 0,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 0 } },

            // 0x88 - 0x8F: RES 1, r
            .{ .handler = RES_B_R8, .mnemonic = "RES 1,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 1,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 1,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 1,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 1,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 1,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 1,(HL)", .Op1 = Op{ .bit = 1 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 1,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 2,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 2,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 2,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 2,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 2,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 2,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 2,(HL)", .Op1 = Op{ .bit = 2 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 2,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 3,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 3,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 3,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 3,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 3,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 3,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 3,(HL)", .Op1 = Op{ .bit = 3 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 3,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 4,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 4,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 4,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 4,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 4,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 4,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 4,(HL)", .Op1 = Op{ .bit = 4 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 4,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 5,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 5,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 5,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 5,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 5,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 5,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 5,(HL)", .Op1 = Op{ .bit = 5 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 5,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 6,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 6,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 6,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 6,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 6,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 6,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 6,(HL)", .Op1 = Op{ .bit = 6 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 6,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 7,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 7,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 7,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 7,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 7,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 7,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = RES_B_HL, .mnemonic = "RES 7,(HL)", .Op1 = Op{ .bit = 7 } },
            .{ .handler = RES_B_R8, .mnemonic = "RES 7,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 0,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 0,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 0,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 0,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 0,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 0,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 0,(HL)", .Op1 = Op{ .bit = 0 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 0,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 0 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 1,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 1,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 1,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 1,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 1,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 1,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 1,(HL)", .Op1 = Op{ .bit = 1 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 1,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 1 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 2,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 2,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 2,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 2,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 2,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 2,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 2,(HL)", .Op1 = Op{ .bit = 2 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 2,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 2 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 3,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 3,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 3,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 3,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 3,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 3,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 3,(HL)", .Op1 = Op{ .bit = 3 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 3,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 3 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 4,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 4,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 4,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 4,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 4,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 4,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 4,(HL)", .Op1 = Op{ .bit = 4 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 4,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 4 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 5,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 5,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 5,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 5,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 5,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 5,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 5,(HL)", .Op1 = Op{ .bit = 5 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 5,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 5 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 6,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 6,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 6,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 6,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 6,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 6,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 6,(HL)", .Op1 = Op{ .bit = 6 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 6,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 6 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 7,B", .Op1 = Op{ .r8 = &c.regs.bc.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 7,C", .Op1 = Op{ .r8 = &c.regs.bc.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 7,D", .Op1 = Op{ .r8 = &c.regs.de.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 7,E", .Op1 = Op{ .r8 = &c.regs.de.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 7,H", .Op1 = Op{ .r8 = &c.regs.hl.hi }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 7,L", .Op1 = Op{ .r8 = &c.regs.hl.lo }, .Op2 = Op{ .bit = 7 } },
            .{ .handler = SET_B_HL, .mnemonic = "SET 7,(HL)", .Op1 = Op{ .bit = 7 } },
            .{ .handler = SET_B_R8, .mnemonic = "SET 7,A", .Op1 = Op{ .r8 = &c.regs.af.a }, .Op2 = Op{ .bit = 7 } },
        };
    }
};

const Instruction = struct {
    handler : *const fn(*SM83,Op,Op)void = undefined,
    mnemonic : [] const u8  = "",
    Op1 : Op = undefined,
    Op2 : Op = undefined,
};

const Opcodefn = fn (cpu: *SM83, Op1 : Op, Op2 : Op) void;

const Op = union(enum){
    r8  : *Register8Bit,
    r16 : *DualRegister,
    bit : u8,
    flag   : struct {type : StatusFlag, state:bool},
};



const Registers = struct {

    af : FlagRegister = undefined,
    bc : DualRegister = undefined,
    de : DualRegister = undefined,
    hl : DualRegister = undefined,
    sp : DualRegister = undefined,
    pc : u16 = 0x100,  // always starts at 0x100
    IF : Register8Bit = undefined,
    IE : Register8Bit = undefined,


    pub fn SetStatusFlag(self: *Registers, flag: StatusFlag, b: bool) void{
        switch (flag) {
            .C => self.af.flags.C = b,
            .H => self.af.flags.H = b,
            .N => self.af.flags.N = b,
            .Z => self.af.flags.Z = b,
        }
    }

    pub fn CheckStatusFlag(self: *Registers, flag: StatusFlag) bool{
        return switch (flag) {
            .C => self.af.flags.C,
            .H => self.af.flags.H,
            .N => self.af.flags.N,
            .Z => self.af.flags.Z,
        };
    }

    pub fn init(parentPtr : *GBC) Registers{
        var r = Registers{};
        // Lets set initial the values
            r.af.a.set(0x11);
            r.af.setFlagByte(0x80);
            r.bc.lo.set(0x00);
            r.sp.set(0xFFFE);
            r.IE.set(0x00);
            r.IF.set(0xE1);

        // compatability mode
        if(!parentPtr.CGBMode){
            // if old license code is 1 or old code is 33 and new code is 1
            const OldLicense:u8 = parentPtr.cart.header.Old_lic_code;
            const NewLicense = std.mem.trimRight(u8, std.mem.asBytes(&parentPtr.cart.header.New_Licensee_Code), "\x00");
            if(OldLicense == 0x1 or (OldLicense == 0x33 and std.mem.eql(u8, NewLicense, "01"))){
               
                // reg B is the sum of all title bytes
                const Title : []u8 = std.mem.asBytes(&parentPtr.cart.header.Title);
                var sum : u8 = 0;
                for(Title) | bytes|{
                    sum +%= bytes;
                }
                r.bc.hi.set(sum);
            }
            else{ // otherwise B is 0
                r.bc.hi.set(0x00);
            }

            r.de.set(0x0008);
            const regB : u8 = r.bc.hi.get();
            if(regB == 0x43 or regB == 0x58) r.hl.set(0x991A) else r.hl.set(0x007C);
        }
        else{ // Regular GBC Mode
            r.bc.hi.set(0x00);
            r.de.set(0xFF56);
            r.hl.set(0x000D);
        }

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

    pub fn setBit(self: *Register8Bit, bit:u3, v:u8)void{
        self.value &= ~(@as(u8,1) << bit);
        self.value |= (v << bit);
    }

    pub fn getBit(self: *Register8Bit, b:u3)u1{
        return @truncate((self.value >> b) & 1);
    }

    pub fn Inc(self:*Register8Bit)void{
        self.value +%= 1;
    }

    pub fn Dec(self:*Register8Bit)void{
        self.value -%= 1;
    }
};

pub const DualRegister = struct {
    lo : Register8Bit,
    hi : Register8Bit,

    pub fn get(self: *DualRegister) u16{
        return (@as(u16,(self.hi.get())) << 8) | self.lo.get();
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


    pub fn getFlagByte(self: *FlagRegister)u8{
        return @bitCast(self.flags);
    }

    pub fn setFlagByte(self: *FlagRegister,v:u8)void{
        self.flags = @bitCast(v);
    }
};

const flagFormat = packed struct {
    padding : u4 = 0x0,
    C : bool = false,
    H : bool = false,
    N : bool = false,
    Z : bool = false,
};

const StatusFlag = enum {
    C,
    H,
    N,
    Z,
};

// Instruction Utils

fn buildAddress(lo: u8, hi : u8) u16{
    return ((@as(u16,hi) << 8) | @as(u16,lo));
}

// Instructions

// Operands usally follow this style

// Single operand, simple u8, bool, 8 bit register, 16 bit register
// can be used as source or Destination

// double operand, Op2 is source, Op2 is destination



// Load Data from one 8 Bit register to another
fn LD_R8_R8(cpu: *SM83, Dest : Op, Src : Op) void
{
    Dest.r8.set(Src.r8.get());
    _ = cpu;
}

// load a 8 bit value into a 8 bit register
fn LD_R8_u8(cpu: *SM83, Dest : Op, Op2 : Op) void 
{
    const n:u8  = cpu.readMem(cpu.regs.pc);
    Dest.r8.set(n);

    _ = Op2;
}

// load a 8 bit value from adress HL into a 8 bit register
fn LD_R8_HL(cpu: *SM83, Dest : Op, Op2 : Op) void 
{
    Dest.r8.set(cpu.readMem(cpu.regs.hl.get()));
    _ = Op2;
}

// load data from an 8 bit register to value at adress HL
fn LD_HL_R8(cpu: *SM83, Src : Op, Op2 : Op) void
{   
    cpu.writeMem(cpu.regs.hl.get(), Src.r8.get());
    _ = Op2;
}

// load a u8 value to the adress specified in HL
fn LD_HL_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);
    cpu.writeMem(cpu.regs.hl.get(), n);

    _ = Op1;
    _ = Op2;
}

fn LD_A_BC(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.bc.get());
    cpu.regs.af.a.set(n);

    _ = Op1;
    _ = Op2;
}

fn LD_A_DE(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.de.get());
    cpu.regs.af.a.set(n);

    _ = Op1;
    _ = Op2;        
}

fn LD_BC_A(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.writeMem(cpu.regs.bc.get(), cpu.regs.af.a.get());
    _ = Op1;
    _ = Op2;  
}

fn LD_DE_A(cpu: *SM83, Op1 : Op, Op2 : Op) void
{
    cpu.writeMem(cpu.regs.de.get(), cpu.regs.af.a.get());
    _ = Op1;
    _ = Op2;         
}

fn LD_A_u16(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.fetch16bits());
    cpu.regs.af.a.set(n);
    _ = Op1;
    _ = Op2; 
}

fn LD_u16_A(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const addr : u16 = cpu.fetch16bits();
    cpu.writeMem(addr, cpu.regs.af.a.get());
    _ = Op1;
    _ = Op2; 
}

fn LDH_A_C(cpu: *SM83, Op1 : Op, Op2 : Op) void
{
    const n : u8 = cpu.readMem(buildAddress(cpu.regs.bc.lo.get(), 0xFF));
    cpu.regs.af.a.set(n);
    _ = Op1;
    _ = Op2; 
}

fn LDH_C_A(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.writeMem(buildAddress(cpu.regs.bc.lo.get(), 0xFF), cpu.regs.af.a.get());
    _ = Op1;
    _ = Op2; 
}

fn LDH_A_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n: u8 = cpu.readMem(cpu.regs.pc);
    const A: u8 = cpu.readMem(buildAddress(n,0xFF));
    cpu.regs.af.a.set(A);
    _ = Op1;
    _ = Op2;
}

fn LDH_u8_A(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n: u8 = cpu.readMem(cpu.regs.pc);
    cpu.writeMem(buildAddress(n,0xFF), cpu.regs.af.a.get());
    _ = Op1;
    _ = Op2;
}
// go back to 36
fn LD_A_HL_DEC(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n: u8 = cpu.readMem(cpu.regs.hl.get());
    cpu.regs.hl.Dec();
    cpu.regs.af.a.set(n);

    _ = Op1;
    _ = Op2;
}

fn LD_HL_DEC_A(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.writeMem(cpu.regs.hl.get(),cpu.regs.af.a.get());
    cpu.regs.hl.Dec();
    _ = Op1;
    _ = Op2;
}

fn LD_A_HL_INC(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n: u8 = cpu.readMem(cpu.regs.hl.get());
    cpu.regs.hl.Inc();
    cpu.regs.af.a.set(n);
    _ = Op1;
    _ = Op2;
}

fn LD_HL_INC_A(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.writeMem(cpu.regs.hl.get(),cpu.regs.af.a.get());
    cpu.regs.hl.Inc();
    _ = Op1;
    _ = Op2;
}

fn LD_R16_u16(cpu: *SM83, Dest : Op, Op2 : Op) void 
{
    const nn : u16 = cpu.fetch16bits();
    Dest.r16.set(nn);
    _ = Op2;
}

fn LD_u16_SP(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const nn : u16 = cpu.fetch16bits();
    cpu.writeMem(nn, cpu.regs.sp.lo.get());
    cpu.writeMem(nn+1, cpu.regs.sp.hi.get());
    _ = Op1;
    _ = Op2;
}

fn LD_SP_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    // requires an extra cycle 
    cpu.regs.sp.set(cpu.regs.hl.get());
    cpu.Emu.cycle();
    _ = Op1;
    _ = Op2;
}

fn PUSH_AF(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{   
    cpu.regs.sp.Dec();
    cpu.Emu.cycle();

    cpu.writeMem(cpu.regs.sp.get(), cpu.regs.af.a.get());
    cpu.regs.sp.Dec();
    cpu.writeMem(cpu.regs.sp.get(), cpu.regs.af.getFlagByte() & 0xF0);
    _ = Op1;
    _ = Op2;
}

fn PUSH_R16(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    cpu.regs.sp.Dec();
    cpu.Emu.cycle();

    cpu.writeMem(cpu.regs.sp.get(), Src.r16.hi.get());
    cpu.regs.sp.Dec();
    cpu.writeMem(cpu.regs.sp.get(), Src.r16.lo.get());

    _ = Op2;
}

fn POP_AF(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.regs.af.setFlagByte(cpu.readMem(cpu.regs.sp.get()) & 0xF0);
    cpu.regs.sp.Inc();
    cpu.regs.af.a.set(cpu.readMem(cpu.regs.sp.get()));
    cpu.regs.sp.Inc();
    _ = Op1;
    _ = Op2;
}

fn POP_R16(cpu: *SM83, Dest : Op, Op2 : Op)void 
{
    Dest.r16.lo.set(cpu.readMem(cpu.regs.sp.get()));
    cpu.regs.sp.Inc();
    Dest.r16.hi.set(cpu.readMem(cpu.regs.sp.get()));
    cpu.regs.sp.Inc();

    _ = Op2;

}

fn LD_HL_SP_E(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const e :i8 = @bitCast(cpu.readMem(cpu.regs.pc));
    const sp : u16 = cpu.regs.sp.get();

    const NewE: u16 = if(e<0) @as(u16,@bitCast(@as(i16,e))) else @as(u16,@as(u8,@bitCast(e)));

    const result:u16 = sp +% NewE;

    const FullCarry: bool = ((sp ^ NewE ^ result)&0x100) != 0;
    const HalfCarry: bool = ((sp ^ NewE ^ result)&0x10) != 0;

    
    cpu.regs.SetStatusFlag(StatusFlag.Z, false);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfCarry);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullCarry);

    cpu.Emu.cycle();

    cpu.regs.hl.set(result);

    _ = Op1;
    _ = Op2;
}

fn ADD_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{

    const FullResult = @addWithOverflow(cpu.regs.af.a.get(), Src.r8.get());
    const HalfResult = @addWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(Src.r8.get())));

    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    cpu.regs.af.a.set(FullResult[0]);

    _ = Op2;
}

fn ADD_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const FullResult = @addWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @addWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    cpu.regs.af.a.set(FullResult[0]);

    _ = Op1;
    _ = Op2;
}

fn ADD_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);

    const FullResult = @addWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @addWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    cpu.regs.af.a.set(FullResult[0]);
    _ = Op1;
    _ = Op2;
}

fn ADC_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const FullResult = @addWithOverflow(cpu.regs.af.a.get(), Src.r8.get());
    const HalfResult = @addWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(Src.r8.get())));

    const CarryAdd = @addWithOverflow(FullResult[0], @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));
    const HalfCarryAdd = @addWithOverflow(@as(u4,@truncate(FullResult[0])), @as(u4,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));

    cpu.regs.SetStatusFlag(StatusFlag.Z, CarryAdd[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0 or HalfCarryAdd[1] != 0 );
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0 or CarryAdd[1] != 0);

    cpu.regs.af.a.set(CarryAdd[0]);

    _ = Op2;
}

fn ADC_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const FullResult = @addWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @addWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    const CarryAdd = @addWithOverflow(FullResult[0], @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));
    const HalfCarryAdd = @addWithOverflow(@as(u4,@truncate(FullResult[0])), @as(u4,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));

    cpu.regs.SetStatusFlag(StatusFlag.Z, CarryAdd[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0 or HalfCarryAdd[1] != 0 );
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0 or CarryAdd[1] != 0);

    cpu.regs.af.a.set(CarryAdd[0]);
    _ = Op1;
    _ = Op2;
}

fn ADC_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);

    const FullResult = @addWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @addWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    const CarryAdd = @addWithOverflow(FullResult[0], @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));
    const HalfCarryAdd = @addWithOverflow(@as(u4,@truncate(FullResult[0])), @as(u4,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));

    cpu.regs.SetStatusFlag(StatusFlag.Z, CarryAdd[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0 or HalfCarryAdd[1] != 0 );
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0 or CarryAdd[1] != 0);

    cpu.regs.af.a.set(CarryAdd[0]);
    _ = Op1;
    _ = Op2;
}

fn SUB_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), Src.r8.get());
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(Src.r8.get())));

    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    cpu.regs.af.a.set(FullResult[0]);

    _ = Op2;
}

fn SUB_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{   
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    cpu.regs.af.a.set(FullResult[0]);

    _ = Op1;
    _ = Op2;
}

fn SUB_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);

    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    cpu.regs.af.a.set(FullResult[0]);

    _ = Op1;
    _ = Op2;
}

fn SBC_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), Src.r8.get());
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(Src.r8.get())));

    const CarrySub = @subWithOverflow(FullResult[0], @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));
    const HalfCarrySub = @subWithOverflow(@as(u4,@truncate(FullResult[0])), @as(u4,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));

    cpu.regs.SetStatusFlag(StatusFlag.Z, CarrySub[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0 or HalfCarrySub[1] != 0 );
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0 or CarrySub[1] != 0);

    cpu.regs.af.a.set(CarrySub[0]);

    _ = Op2;

}

fn SBC_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());
    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    const CarrySub = @subWithOverflow(FullResult[0], @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));
    const HalfCarrySub = @subWithOverflow(@as(u4,@truncate(FullResult[0])), @as(u4,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));

    cpu.regs.SetStatusFlag(StatusFlag.Z, CarrySub[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0 or HalfCarrySub[1] != 0 );
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0 or CarrySub[1] != 0);

    cpu.regs.af.a.set(CarrySub[0]);
    _ = Op1;
    _ = Op2;
}

fn SBC_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);
    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));

    const CarrySub = @subWithOverflow(FullResult[0], @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));
    const HalfCarrySub = @subWithOverflow(@as(u4,@truncate(FullResult[0])), @as(u4,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))));

    cpu.regs.SetStatusFlag(StatusFlag.Z, CarrySub[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0 or HalfCarrySub[1] != 0 );
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0 or CarrySub[1] != 0);

    cpu.regs.af.a.set(CarrySub[0]);
    _ = Op1;
    _ = Op2;
}

// same as SUBR8 but does not update register A
fn CP_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), Src.r8.get());
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(Src.r8.get())));

    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    _ = Op2;
}

fn CP_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());
    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));


    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);
    _ = Op1;
    _ = Op2;
}

fn CP_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);
    const FullResult = @subWithOverflow(cpu.regs.af.a.get(), n);
    const HalfResult = @subWithOverflow(@as(u4,@truncate(cpu.regs.af.a.get())), @as(u4,@truncate(n)));


    cpu.regs.SetStatusFlag(StatusFlag.Z, FullResult[0] == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfResult[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullResult[1] != 0);

    _ = Op1;
    _ = Op2;
}

fn INC_R8(cpu: *SM83, Reg : Op, Op2 : Op) void 
{
    const HalfCarry = @addWithOverflow(@as(u4,@truncate(Reg.r8.get())), @as(u4,1));
    Reg.r8.Inc();

    cpu.regs.SetStatusFlag(StatusFlag.Z, Reg.r8.get() == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfCarry[1] != 0 );

    _ = Op2;
}

fn INC_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const result : u8 = n +% 1;
    const HalfCarry = @addWithOverflow(@as(u4,@truncate(n)), @as(u4,1));

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfCarry[1] != 0 );

    cpu.writeMem(cpu.regs.hl.get(), result);
    _ = Op1;
    _ = Op2;
}

fn DEC_R8(cpu: *SM83, Reg : Op, Op2 : Op) void 
{
    const HalfCarry = @subWithOverflow(@as(u4,@truncate(Reg.r8.get())), @as(u4,1));
    Reg.r8.Dec();

    cpu.regs.SetStatusFlag(StatusFlag.Z, Reg.r8.get() == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfCarry[1] != 0 );

    _ = Op2;
}

fn DEC_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const result : u8 = n -% 1;
    const HalfCarry = @subWithOverflow(@as(u4,@truncate(n)), @as(u4,1));

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfCarry[1] != 0 );

    cpu.writeMem(cpu.regs.hl.get(), result);
    _ = Op1;
    _ = Op2;
}

fn AND_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{   
    const result = cpu.regs.af.a.get() & Src.r8.get();

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, true);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    _ = Op2;
}

fn AND_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());
    const result = cpu.regs.af.a.get() & n;

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, true);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    _ = Op1;
    _ = Op2;
}

fn AND_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);
    const result = cpu.regs.af.a.get() & n;

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, true);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    _ = Op1;
    _ = Op2;
}

fn OR_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const result = cpu.regs.af.a.get() | Src.r8.get();

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    
    _ = Op2;
}

fn OR_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());
    const result = cpu.regs.af.a.get() | n;

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    _ = Op1;
    _ = Op2;
}

fn OR_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);
    const result = cpu.regs.af.a.get() | n;

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    _ = Op1;
    _ = Op2;
}

fn XOR_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const result = cpu.regs.af.a.get() ^ Src.r8.get();

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    
    _ = Op2;
}

fn XOR_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());
    const result = cpu.regs.af.a.get() ^ n;

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    _ = Op1;
    _ = Op2;
}

fn XOR_u8(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.pc);
    const result = cpu.regs.af.a.get() ^ n;

    cpu.regs.SetStatusFlag(StatusFlag.Z, result == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.regs.af.a.set(result);
    _ = Op1;
    _ = Op2;
}

fn CCF(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, !cpu.regs.CheckStatusFlag(StatusFlag.C));
    _ = Op1;
    _ = Op2;
}

fn SCF(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, true);
    _ = Op1;
    _ = Op2;
}

fn DAA(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    // https://ehaskins.com/2018-01-30%20Z80%20DAA/ 
    var v : u8 = cpu.regs.af.a.get();
    const n : bool = cpu.regs.CheckStatusFlag(StatusFlag.N);
    const h : bool = cpu.regs.CheckStatusFlag(StatusFlag.H);
    const c : bool = cpu.regs.CheckStatusFlag(StatusFlag.C);

    var correction : u8 = 0;

    if (h or (!n and (v & 0xf) > 9)) {
        correction |= 0x6;
    }

    if (c or (!n and v > 0x99)) {
        correction |= 0x60;
        cpu.regs.SetStatusFlag(StatusFlag.C, true);
    }

    if(n) v -%= correction else v +%=correction;

    cpu.regs.af.a.set(v);
    cpu.regs.SetStatusFlag(StatusFlag.Z, v == 0);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    _ = Op1;
    _ = Op2;
        
}

fn CPL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{

    cpu.regs.af.a.set(~cpu.regs.af.a.get());

    cpu.regs.SetStatusFlag(StatusFlag.N, true);
    cpu.regs.SetStatusFlag(StatusFlag.H, true);
    _ = Op1;
    _ = Op2;
}

fn INC_R16(cpu: *SM83, Reg16 : Op, Op2 : Op) void 
{
    Reg16.r16.Inc();
    //Requires an extra cycle
    cpu.Emu.cycle();

    _ = Op2;
}

fn DEC_R16(cpu: *SM83, Reg16 : Op, Op2 : Op) void 
{
    Reg16.r16.Dec();
    //Requires an extra cycle
    cpu.Emu.cycle();

    _ = Op2;
}

fn ADD_HL_R16(cpu: *SM83, Reg16 : Op, Op2 : Op) void 
{
    const FullCarry = @addWithOverflow(cpu.regs.hl.get(), Reg16.r16.get());
    const HalfCarry = @addWithOverflow(@as(u12,@truncate(cpu.regs.hl.get())), @as(u12,@truncate(Reg16.r16.get())));
    
    
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfCarry[1] != 0);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullCarry[1] != 0);
    
    cpu.regs.hl.set(FullCarry[0]);

    //Requires an extra cycle
    cpu.Emu.cycle();

    _ = Op2;
}

fn ADD_SP_E(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const e :i8 = @bitCast(cpu.readMem(cpu.regs.pc));
    const sp : u16 = cpu.regs.sp.get();

    const NewE: u16 = if(e<0) @as(u16,@bitCast(@as(i16,e))) else @as(u16,@as(u8,@bitCast(e)));

    const result:u16 = sp +% NewE;

    const FullCarry: bool = ((sp ^ NewE ^ result)&0x100) != 0;
    const HalfCarry: bool = ((sp ^ NewE ^ result)&0x10) != 0;
    
    cpu.regs.SetStatusFlag(StatusFlag.Z, false);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, HalfCarry);
    cpu.regs.SetStatusFlag(StatusFlag.C, FullCarry);

    // two extra cycles
    cpu.Emu.cycle();
    cpu.Emu.cycle();

    cpu.regs.sp.set(result);
    _ = Op1;
    _ = Op2;

}

fn RLCA(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{

    const b7 : u8 = @as(u8,cpu.regs.af.a.getBit(7));
    const RotateLeft = (cpu.regs.af.a.get() << 1) | b7;

    cpu.regs.SetStatusFlag(StatusFlag.Z, false);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    cpu.regs.af.a.set(RotateLeft);
    _ = Op1;
    _ = Op2;
}

fn RR_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const b0 = @as(u8,Src.r8.getBit(0));
    const RotateRight: u8 = (@as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))) << 7) | (Src.r8.get() >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    Src.r8.set(RotateRight);

    _ = Op2;
}

fn RR_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const b0 = n & 1;
    const RotateRight: u8 = (@as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))) << 7) | (n >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    cpu.writeMem(cpu.regs.hl.get(), RotateRight);
    _ = Op1;
    _ = Op2;
}

fn RRA(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const b0 = @as(u8,cpu.regs.af.a.getBit(0));
    const RotateRight: u8 = (@as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C))) << 7) | (cpu.regs.af.a.get() >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, false);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    cpu.regs.af.a.set(RotateRight);
    _ = Op1;
    _ = Op2;
}

fn RRC_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const b0 = @as(u8,Src.r8.getBit(0));
    const RotateRight: u8 = (b0 << 7) | (Src.r8.get() >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    Src.r8.set(RotateRight);

    _ = Op2;

}

fn RRC_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const b0 = n & 1;
    const RotateRight: u8 = (b0 << 7) | (n >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    cpu.writeMem(cpu.regs.hl.get(), RotateRight);
    _ = Op1;
    _ = Op2;
}

fn RRCA(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const b0 = @as(u8,cpu.regs.af.a.getBit(0));
    const RotateRight: u8 = (b0 << 7) | (cpu.regs.af.a.get() >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, false);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    cpu.regs.af.a.set(RotateRight);
    _ = Op1;
    _ = Op2;
}

fn RL_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const b7 = @as(u8,Src.r8.getBit(7));
    const RotateLeft: u8 = (Src.r8.get() << 1) | @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C)));

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateLeft == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    Src.r8.set(RotateLeft);

    _ = Op2;
}

fn RL_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{   
    const n = cpu.readMem(cpu.regs.hl.get());
    const b7 = (n & 0x80) >> 7;
    const RotateLeft: u8 = (n << 1) | @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C)));

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateLeft == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    cpu.writeMem(cpu.regs.hl.get(), RotateLeft);
    _ = Op1;
    _ = Op2;
}

fn RLA(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const b7 = @as(u8,cpu.regs.af.a.getBit(7));
    const RotateLeft: u8 = (cpu.regs.af.a.get() << 1) | @as(u8,@intFromBool(cpu.regs.CheckStatusFlag(StatusFlag.C)));

    cpu.regs.SetStatusFlag(StatusFlag.Z, false);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    cpu.regs.af.a.set(RotateLeft);
    _ = Op1;
    _ = Op2;
}

fn RLC_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const b7 = @as(u8,Src.r8.getBit(7));
    const RotateLeft: u8 = (Src.r8.get() << 1) | b7;

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateLeft == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    Src.r8.set(RotateLeft);

    _ = Op2;
}

fn RLC_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n = cpu.readMem(cpu.regs.hl.get());
    const b7 = (n & 0x80) >> 7;
    const RotateLeft: u8 = (n << 1) | b7;

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateLeft == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    cpu.writeMem(cpu.regs.hl.get(), RotateLeft);

    _ = Op1;
    _ = Op2;
}

fn SLA_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{
    const b7 = @as(u8,Src.r8.getBit(7));
    const RotateLeft: u8 = Src.r8.get() << 1;

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateLeft == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    Src.r8.set(RotateLeft);

    _ = Op2;
}

fn SLA_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n = cpu.readMem(cpu.regs.hl.get());
    const b7 = (n & 0x80) >> 7;
    const RotateLeft: u8 = n << 1;

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateLeft == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b7 != 0);

    cpu.writeMem(cpu.regs.hl.get(), RotateLeft);
    _ = Op1;
    _ = Op2;
}

fn SRA_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{   
    const b7 = @as(u8,Src.r8.getBit(7));
    const b0 = @as(u8,Src.r8.getBit(0));
    const RotateRight: u8 = (b7 << 7) | (Src.r8.get() >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    Src.r8.set(RotateRight);

    _ = Op2;
    
}

fn SRA_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const b7 = (n & 0x80) >> 7;
    const b0 = n & 1;
    const RotateRight: u8 = (b7 << 7) | (n >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    cpu.writeMem(cpu.regs.hl.get(), RotateRight);
    _ = Op1;
    _ = Op2;
}

fn SRL_R8(cpu: *SM83, Src: Op, Op2 : Op) void 
{
    const b0 = @as(u8,Src.r8.getBit(0));
    const RotateRight: u8 = (Src.r8.get() >> 1);

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    Src.r8.set(RotateRight);

    _ = Op2;
}

fn SRL_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const b0 = n & 1;
    const RotateRight: u8 = n >> 1;

    cpu.regs.SetStatusFlag(StatusFlag.Z, RotateRight == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, b0 != 0);

    cpu.writeMem(cpu.regs.hl.get(), RotateRight);
    _ = Op1;
    _ = Op2;
}

fn SWAP_R8(cpu: *SM83, Src : Op, Op2 : Op) void 
{

    const temp: u8 = Src.r8.get();
    Src.r8.set(((temp&0xF) << 4) | ((temp&0xF0) >> 4));

    cpu.regs.SetStatusFlag(StatusFlag.Z, Src.r8.get() == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    _ = Op2;
}

fn SWAP_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());

    const swap = ((n&0xF) << 4) | ((n&0xF0) >> 4);

    cpu.regs.SetStatusFlag(StatusFlag.Z, swap == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, false);
    cpu.regs.SetStatusFlag(StatusFlag.C, false);

    cpu.writeMem(cpu.regs.hl.get(), swap);
    _ = Op1;
    _ = Op2;
}

fn BIT_B_R8(cpu: *SM83, Src : Op, bit : Op) void 
{
    cpu.regs.SetStatusFlag(StatusFlag.Z, Src.r8.getBit(@truncate(bit.bit)) == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, true);
}

fn BIT_B_HL(cpu: *SM83, bit : Op, Op2 : Op) void 
{
    const n : u8 = cpu.readMem(cpu.regs.hl.get());
    cpu.regs.SetStatusFlag(StatusFlag.Z, (n >> (@as(u3,@truncate(bit.bit))))&1 == 0);
    cpu.regs.SetStatusFlag(StatusFlag.N, false);
    cpu.regs.SetStatusFlag(StatusFlag.H, true);

    _ = Op2;

}

fn RES_B_R8(cpu: *SM83, Src : Op, bit : Op) void 
{
    Src.r8.setBit(@truncate(bit.bit), 0);
    _ = cpu;
}

fn RES_B_HL(cpu: *SM83, bit : Op, Op2 : Op) void 
{
    var n : u8 = cpu.readMem(cpu.regs.hl.get());
    n &= ~(@as(u8,1) << @truncate(bit.bit));
    cpu.writeMem(cpu.regs.hl.get(), n);

    _ = Op2;
}

fn SET_B_R8(cpu: *SM83, Src : Op, bit : Op) void 
{
    Src.r8.setBit(@truncate(bit.bit), 1);
    _ = cpu;
}

fn SET_B_HL(cpu: *SM83, bit : Op, Op2 : Op) void 
{
    var n : u8 = cpu.readMem(cpu.regs.hl.get());
    n |= (@as(u8,1) << @truncate(bit.bit));
    cpu.writeMem(cpu.regs.hl.get(), n);

    _ = Op2;
}

fn JP_u16(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const address : u16 = cpu.fetch16bits();
    cpu.regs.pc = address;

    //Requires an extra cycle
    cpu.Emu.cycle();
    _ = Op1;
    _ = Op2;
}

fn JP_HL(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.regs.pc = cpu.regs.hl.get();
    _ = Op1;
    _ = Op2;
}

fn JP_CC_u16(cpu: *SM83, CC : Op, Op2 : Op) void 
{
    const address : u16 = cpu.fetch16bits();

    if (cpu.regs.CheckStatusFlag(CC.flag.type) == CC.flag.state)
    {
        cpu.regs.pc = address;

        //Requires an extra cycle
        cpu.Emu.cycle();
    }

    _ = Op2;
}

fn JR_E(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{   
    const e:u16  = @bitCast(@as(i16,@intCast(@as(i8,@bitCast(cpu.readMem(cpu.regs.pc))))));

    cpu.regs.pc +%=  e;

    //Requires an extra cycle
    cpu.Emu.cycle();
    _ = Op1;
    _ = Op2;
}

fn JR_CC_E(cpu: *SM83, CC : Op, Op2 : Op) void 
{
    const e:u16  = @bitCast(@as(i16,@intCast(@as(i8,@bitCast(cpu.readMem(cpu.regs.pc))))));

    if(cpu.regs.CheckStatusFlag(CC.flag.type) == CC.flag.state)
    {

        cpu.regs.pc +%=  e;

        //Requires an extra cycle
        cpu.Emu.cycle();
    }

    _ = Op2;
}

fn CALL_u16(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const address : u16 = cpu.fetch16bits();
    cpu.regs.sp.Dec();
    cpu.writeMem(cpu.regs.sp.get(),@truncate(cpu.regs.pc >> 8));
    cpu.regs.sp.Dec();
    cpu.writeMem(cpu.regs.sp.get(),@truncate(cpu.regs.pc));
    cpu.regs.pc = address;
    //Requires an extra cycle
    cpu.Emu.cycle();
    _ = Op1;
    _ = Op2;

}

fn CALL_CC_u16(cpu: *SM83, CC : Op, Op2 : Op) void 
{
    const address : u16 = cpu.fetch16bits();
    if (cpu.regs.CheckStatusFlag(CC.flag.type) == CC.flag.state)
    {
        cpu.regs.sp.Dec();
        cpu.writeMem(cpu.regs.sp.get(),@truncate(cpu.regs.pc >> 8));
        cpu.regs.sp.Dec();
        cpu.writeMem(cpu.regs.sp.get(),@truncate(cpu.regs.pc));
        cpu.regs.pc = address;
        //Requires an extra cycle
        cpu.Emu.cycle();
    }

    _ = Op2;
}

fn RET(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const lsb: u8 = cpu.readMem(cpu.regs.sp.get());
    cpu.regs.sp.Inc();
    const msb: u8 = cpu.readMem(cpu.regs.sp.get());
    cpu.regs.sp.Inc();

    cpu.regs.pc = buildAddress(lsb, msb);
    cpu.Emu.cycle();
    _ = Op1;
    _ = Op2;
}

fn RET_CC(cpu: *SM83, CC : Op, Op2 : Op) void 
{
    if(cpu.regs.CheckStatusFlag(CC.flag.type) == CC.flag.state)
    {
        const lsb: u8 = cpu.readMem(cpu.regs.sp.get());
        cpu.regs.sp.Inc();
        const msb: u8 = cpu.readMem(cpu.regs.sp.get());
        cpu.regs.sp.Inc();

        cpu.regs.pc = buildAddress(lsb, msb);
        cpu.Emu.cycle();
    }
    //Requires an extra cycle
    cpu.Emu.cycle(); // TODO: Check if this is necessary
    _ = Op2;
}

fn RETI(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    const lsb: u8 = cpu.readMem(cpu.regs.sp.get());
    cpu.regs.sp.Inc();
    const msb: u8 = cpu.readMem(cpu.regs.sp.get());
    cpu.regs.sp.Inc();

    cpu.regs.pc = buildAddress(lsb, msb);
    cpu.Emu.cycle();

    cpu.IMEWait = true;
    cpu.IMEWaitCount = 0;

    _ = Op1;
    _ = Op2;
}

fn RST_u8(cpu: *SM83, n : Op, Op2 : Op) void 
{
    cpu.regs.sp.Dec();
    cpu.writeMem(cpu.regs.sp.get(),@truncate(cpu.regs.pc >> 8));
    cpu.regs.sp.Dec();
    cpu.writeMem(cpu.regs.sp.get(),@truncate(cpu.regs.pc));

    cpu.regs.pc = buildAddress(n.bit, 0x00);

    //Requires an extra cycle
    cpu.Emu.cycle();
    _ = Op2;
}

//Look more into this
fn HALT(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    if (cpu.IME)
    {
        // already wakes up and calls the interrupt normally
    }
    else
    {
        if((cpu.regs.IE.get() & cpu.regs.IF.get()) != 0)
        {
            cpu.HaltBug = true;
        }
        else
        {
            cpu.isHalted = true;
            
            // VRAM dma halts until we leave halted state
            cpu.dmaWasActive = cpu.Emu.dma.VRAMTransferInProgress; 
            cpu.Emu.dma.VRAMTransferInProgress = false;
        }
    }
    _ = Op1;
    _ = Op2;
}

fn STOP(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    // if double speed is set and armed then we swap to a different speed
    if(cpu.Emu.DoubleSpeed.Armed)
    {
        cpu.Emu.DoubleSpeed.Active = !cpu.Emu.DoubleSpeed.Active;
        cpu.Emu.DoubleSpeed.Armed = false;
    } 
        
    _ = Op1;
    _ = Op2;
}

fn DI(cpu: *SM83, Op1 : Op, Op2 : Op) void 
{
    cpu.IME = false;
    cpu.IMEWait = false;
    cpu.IMEWaitCount = 0;
    _ = Op1;
    _ = Op2;
}

fn EI(cpu: *SM83, Op1 : Op, Op2 : Op) void
{
    cpu.IMEWait = true;
    cpu.IMEWaitCount = 0;
    _ = Op1;
    _ = Op2;
}

fn NOP(cpu: *SM83, Op1 : Op, Op2 : Op) void
{
    //nothing
    _ = cpu;
    _ = Op1;
    _ = Op2;
}



