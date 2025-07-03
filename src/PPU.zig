const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const Register = @import("SM83.zig").Register8Bit;

const GUI = @import("GUI.zig").GUI;


pub const PPU = struct {

    LCD : *GUI,

    Emu : *GBC,
    vram : VRAM,
    oam : OAM,
    pmem : PaletteMemory,

    regs : Registers,
    mode : PPUmodes = PPUmodes.OAMScan,

    sprites : [10]usize = .{0xFF}**10,
    spriteCount : usize = 0,

    var dots: u32 = 0;

    var windowline:u8 = 0;

    const DotsPerFrame:u32 = 70224;


    pub fn init (parentPtr : *GBC, lcd : *GUI) PPU{

        dots = 0;

        return PPU{
            .LCD = lcd,
            .Emu = parentPtr,
            .vram = VRAM{},
            .oam = OAM{},
            .regs = Registers.init(),
            .pmem = PaletteMemory{},
        };

    }

    pub fn tick(self: *PPU) void{

        dots +%= 1;

        if(!self.regs.lcdc.LCDPPUEnable){
            if(dots >= DotsPerFrame){
                dots -= DotsPerFrame;
            }
            return;
        }

        switch (self.mode) {
            .OAMScan => {

                if(dots >= 80)
                {
                    if(self.Emu.CGBMode) self.scanOAMCGB() else self.scanOAMDMG(); // scans the oam 
                    dots -= 80;
                    self.mode = PPUmodes.DrawingPixels;
                    self.regs.stat.PPUmode = self.mode;
                }
            },
            .DrawingPixels => {

                if(dots >= 172){
                    self.DrawScanline2();

                    dots -= 172;
                    self.mode = PPUmodes.HBlank;
                    self.regs.stat.PPUmode = self.mode;

                    if(self.regs.stat.Mode0Int){
                        self.Emu.cpu.regs.IF.setBit(1, 1);
                    }
                }

            },
            .HBlank => {    
            
                if(dots >= 204)
                {
                    // DMA
                    self.Emu.dma.Hblank();

                    dots -= 204;
                    self.mode = PPUmodes.OAMScan;

                    self.regs.ly.Inc();
                    self.compareLY_LYC();

                    if(self.regs.ly.get() == 144){

                        // Notify our parent that a frame has been finished
                        self.Emu.FrameFinished = true;

                        self.mode = PPUmodes.VBlank;
                        self.regs.stat.PPUmode = self.mode;

                        // Request Interrupts accordingly
                        self.Emu.cpu.regs.IF.setBit(0, 1);

                        if(self.regs.stat.Mode1Int){
                            self.Emu.cpu.regs.IF.setBit(1, 1);
                        }
                    }
                    else{
                        self.regs.stat.PPUmode = self.mode;

                        if(self.regs.stat.Mode2Int){
                            self.Emu.cpu.regs.IF.setBit(1, 1);
                        }
                    }
                }
                
            },
            .VBlank => {

                if(dots >= 456){
                    dots -= 456;
                    self.regs.ly.Inc();

                    if(self.regs.ly.get() == 154){

                        // reset window Line
                        windowline = 0;

                        self.regs.ly.set(0);
                        self.compareLY_LYC();

                        self.mode = PPUmodes.OAMScan;
                        self.regs.stat.PPUmode = self.mode;

                        if(self.regs.stat.Mode2Int){
                            self.Emu.cpu.regs.IF.setBit(1, 1);
                        }

                    }
                    else{
                        self.compareLY_LYC();
                    }
                }
            },
        }
    }

    fn DrawScanline2(self: *PPU)void{

        const LY:u8 = self.regs.ly.get();
        const WY:u8 = self.regs.wy.get();
        const WX:u8 = self.regs.wx.get() -% 7;
        const scx:u8 = self.regs.scx.get();
        const scy:u8 = self.regs.scy.get();
        const lcdc = self.regs.lcdc;
        
        var BGindexCache : [160]u8 = undefined;
        var BGAttributeCache : [160]u1 = undefined; // traps the priority of BGB pixels

        var X: u8 = 0;
        var BitsPlaced:u8 = 0;
        var windowTileSeen: bool = false;

        while (X < 160) :(X+=BitsPlaced){
            var tileMap : u16 = 0x9800;
            var tileData : u16 = 0x9000;
            var WindowTile : bool = false;  
             // Set up what maps and tile data to look at
            if(lcdc.WindowEnable and LY >= WY and X >= WX){
                windowTileSeen = true;
                WindowTile = true;
                if(lcdc.WindowTileMap) tileMap = 0x9C00;

            }
            if(!WindowTile and lcdc.BGtileMap) tileMap = 0x9C00;
            if(lcdc.BGWinTileData) tileData = 0x8000;

            // initalize our Y and X position
            var y:u8 = 0;
            var x:u8 = X;

            if(WindowTile) {x -%= WX; y = windowline;} else {x +%= scx; y = scy +% LY;}
            // Now that we have our coords we can grab out tile index  and attributes
            const Tile_Attr_Address : u16 = @as(u16,tileMap-0x8000) + (@as(u16,y/8)*32) + (@as(u16,x/8));
            
            const BG_Attr : BGMapAtrributes = @bitCast(self.vram.Banks[1][Tile_Attr_Address]);
            

            const tileIndex: u8 = self.vram.Banks[0][Tile_Attr_Address];
            
            const tileOffset: u16 = if (tileData == 0x8000)
                @as(u16, tileIndex ) * 16 // unsigned
            else
                @bitCast(@as(i16, @as(i8, @bitCast(tileIndex))) * 16); // signed, preserve sign when used as offset

            // Calculate yOffset with or without flip
            const yOffset: u16 = if(BG_Attr.Yflip and self.Emu.CGBMode) (7-(y&7))*2 else (y&7)*2;
            // Lastly calculate final address using tile datat tileoffset and yoffset
            const BG_Address : u16 = @as(u16,tileData - 0x8000) +% tileOffset +% yOffset;

            const BGLo: u8 = self.vram.Banks[if(self.Emu.CGBMode) BG_Attr.Bank else 0][BG_Address];
            const BGHi: u8 = self.vram.Banks[if(self.Emu.CGBMode) BG_Attr.Bank else 0][BG_Address + 1];

            const BGPallete = self.pmem.grabPalette(if(self.Emu.CGBMode) BG_Attr.ColorPalette else 0, true); 

            BitsPlaced = 0;
            var offset: u8 = x&7;
            while (offset < 8) :(offset += 1) {
                
                if (X + offset > 159) break; // clamps end

                const BGLoBit :u8 = (BGLo >> if(BG_Attr.XFlip and self.Emu.CGBMode) @truncate(offset) else @truncate(7-offset)) & 1;
                const BGHiBit :u8 = (BGHi >> if(BG_Attr.XFlip and self.Emu.CGBMode) @truncate(offset) else @truncate(7-offset)) & 1;
                const BGindex : u8 = (BGHiBit << 1) | BGLoBit;

                BGindexCache[X+BitsPlaced] = BGindex;
                BGAttributeCache[X+BitsPlaced] = BG_Attr.Priority;
                // we can do cach here and then save to write later hmmmm

                self.LCD.PlacePixel(X + BitsPlaced, LY, BGPallete[BGindex]);
                
                // these bits will be added to X on next cycle
                BitsPlaced += 1;
            }

        }   

        var X2: i16 = -7;
        var Sprite: OAMEntry = undefined;
        while (X2 < 160) : (X2 += 1){
            var i : usize = 0;
            while(i<self.spriteCount) : (i+=1){
                if(self.sprites[i] != 0xFF){
                    if(X2+8 == @as(i16,@intCast(self.oam.Entries[self.sprites[i]].X))){

                        Sprite = self.oam.Entries[self.sprites[i]];

                        const SpriteHeight :u8 = if(lcdc.OBJsize) 16 else 8;
                        const SpriteY = if(Sprite.YFlip) (SpriteHeight-1) - (LY + 16 - Sprite.Y) else (LY + 16 - Sprite.Y);

                        const SpriteLo:u8 = self.vram.Banks[if(self.Emu.CGBMode) Sprite.Bank_No else 0][(@as(u32,(Sprite.tile))*16) + @as(u32,SpriteY) * 2];
                        const SpriteHi:u8 = self.vram.Banks[if(self.Emu.CGBMode) Sprite.Bank_No else 0][(@as(u32,(Sprite.tile))*16) + @as(u32,SpriteY) * 2 + 1]; 
                        const OBJPalette = self.pmem.grabPalette(if(self.Emu.CGBMode) Sprite.CGB_Palette else @as(u3,Sprite.Palette), false);

                        var offset: u8 = 0;
                        while (offset < 8) : (offset += 1){
                            
                            if(X2 + @as(i16,@intCast(offset)) > 159) break;
                            if(X2 + @as(i16,@intCast(offset)) < 0) continue;

                            const CurrentX : u8 = @intCast(X2 + @as(i16,@intCast(offset)));

                            const SpriteLoBit :u8 = (SpriteLo >> if(Sprite.XFlip) @truncate(offset) else @truncate(7 - offset)) & 1;
                            const SpriteHiBit :u8 = (SpriteHi >> if(Sprite.XFlip) @truncate(offset) else @truncate(7 - offset)) & 1;
                            const OBJIndex:u8 = (SpriteHiBit << 1 | SpriteLoBit);

                            if(self.Emu.CGBMode){
                                const ProrityBitmap :u3 = ((@as(u3,lcdc.BGWindowPriority)<<2)|(@as(u3,Sprite.Priority)<<1)|@as(u3,BGAttributeCache[CurrentX]));

                                const BGPriority:bool = switch (ProrityBitmap) {
                                    0b101 => (BGindexCache[CurrentX] != 0), // if BG color is 1-3 OBJ priority is false
                                    0b110 => (BGindexCache[CurrentX] != 0),
                                    0b111 => (BGindexCache[CurrentX] != 0),
                                    else => false, // OBJ Wins
                                };

                                if(!BGPriority and OBJIndex != 0) self.LCD.PlacePixel(CurrentX, LY, OBJPalette[OBJIndex]);
                            }else{
                                if(OBJIndex != 0x00){

                                    if(Sprite.Priority == 1){

                                        if(BGindexCache[CurrentX] == 0x00){
                                            self.LCD.PlacePixel(CurrentX, LY, OBJPalette[OBJIndex]); 
                                        }
                                    }
                                    else{
                                        self.LCD.PlacePixel(CurrentX, LY, OBJPalette[OBJIndex]);
                                    }
                                }
                            }
                        }
                    }
                }
            }

        }   

        if(windowTileSeen){
            windowline += 1;
        } 
    }

    // fn DrawScanline(self: *PPU)void{

    //     const LY:u8 = self.regs.ly.get();
    //     const WY:u8 = self.regs.wy.get();
    //     const WX:u8 = self.regs.wx.get() -% 7;
    //     const scx:u8 = self.regs.scx.get();
    //     const scy:u8 = self.regs.scy.get();
    //     const lcdc = self.regs.lcdc;
        
    //     var BGindexCache : [160]u8 = undefined;
    //     var BGAttributeCache : [20]BGMapAtrributes = undefined;
    //     // Here we will do a frist pass for only the background pixels
    //     var X : u8 = 0;
    //     var TileX : u8 = 0;
    //     while(X < 160): (X += 8-TileX){
    //         // Set up what maps and tile data to look at
    //         var tileMap : u16 = 0x9800;
    //         var tileData : u16 = 0x9000;
    //         var WindowTile : bool = false;  
    //         if(lcdc.WindowEnable){

    //             if(LY >= WY and X+7 >= self.regs.wx.get()) {
    //                 WindowTile = true;
    //                 if(lcdc.WindowTileMap) tileMap = 0x9C00;
    //             }
    //         }

    //         if(!WindowTile and lcdc.BGtileMap) tileMap = 0x9C00;
    //         if(lcdc.BGWinTileData) tileData = 0x8000;

    //         // initalize our Y and X position
    //         var y:u8 = 0;
    //         var x:u8 = X;

    //         if(WindowTile) {
    //             x -%= WX; 
    //             y = (LY -% WY)&255;

    //         } else {
    //             x +%= scx; 
    //             y = scy +% LY;
    //         }

    //         // Now that we have our coords we can grab out tile index  and attributes
    //         const Tile_Attr_Address : u16 = @as(u16,tileMap-0x8000) + (@as(u16,y/8)*32) + (@as(u16,x/8));
            
    //         const BG_Attr : BGMapAtrributes = @bitCast(self.vram.Banks[1][Tile_Attr_Address]);
    //         BGAttributeCache[X/8] = BG_Attr;

    //         const tileIndex: u8 = self.vram.Banks[0][Tile_Attr_Address];
            
    //         const tileOffset: u16 = if (tileData == 0x8000)
    //             @as(u16, tileIndex ) * 16 // unsigned
    //         else
    //             @bitCast(@as(i16, @as(i8, @bitCast(tileIndex))) * 16); // signed, preserve sign when used as offset

    //         // Calculate yOffset with or without flip
    //         const yOffset: u16 = if(BG_Attr.Yflip and self.Emu.CGBMode) (7-(y&7))*2 else (y&7)*2;
    //         // Lastly calculate final address using tile datat tileoffset and yoffset
    //         const BG_Address : u16 = @as(u16,tileData - 0x8000) +% tileOffset +% yOffset;

    //         const BGLo: u8 = self.vram.Banks[if(self.Emu.CGBMode) BG_Attr.Bank else 0][BG_Address];
    //         const BGHi: u8 = self.vram.Banks[if(self.Emu.CGBMode) BG_Attr.Bank else 0][BG_Address + 1];

    //         const BGPallete = self.pmem.grabPalette(if(self.Emu.CGBMode) BG_Attr.ColorPalette else 0, true); 
        
    //         TileX = x&7;

    //         var bit:u3 = @truncate(TileX);
    //         while(true){

    //             const BGLoBit :u8 = (BGLo >> if(BG_Attr.XFlip and self.Emu.CGBMode) bit else 7-bit) & 1;
    //             const BGHiBit :u8 = (BGHi >> if(BG_Attr.XFlip and self.Emu.CGBMode) bit else 7-bit) & 1;
    //             const BGindex : u8 = (BGHiBit << 1) | BGLoBit;

    //             // If we Out of bound screen finished
    //             if((X + bit) > 159) break;

    //             // used for sprites later on
    //             BGindexCache[X+bit - TileX] = BGindex;
    //             // Lets set The bit initially to BG color
    //             self.LCD.PlacePixel(X+bit-TileX, LY, BGPallete[BGindex]);
    //             //self.screen[X+bit - TileX][LY] = BGPallete[BGindex];

    //             if(bit == 7) break;
    //             bit +%= 1;
    //         }
    //     }

    //     var X2 : i32 = - 8; // this allows us to see sprites that are halfway off screen
    //     var Sprite: OAMEntry = undefined;
    //     while(X2 < 160) : (X2 += 1){
    //         var i : usize = 0;
    //         while(i<spriteCount) : (i+=1){
    //             if(X2+8 == self.oam.Entries[sprites[i]].X){

    //                 Sprite = self.oam.Entries[sprites[i]];
    //                 const SpriteHeight :u8 = if(lcdc.OBJsize) 16 else 8;
    //                 const SpriteY = if(Sprite.YFlip) (SpriteHeight-1) - (LY + 16 - Sprite.Y) else (LY + 16 - Sprite.Y);

    //                 const SpriteLo:u8 = self.vram.Banks[if(self.Emu.CGBMode) Sprite.Bank_No else 0][(@as(u32,(Sprite.tile))*16) + @as(u32,SpriteY) * 2];
    //                 const SpriteHi:u8 = self.vram.Banks[if(self.Emu.CGBMode) Sprite.Bank_No else 0][(@as(u32,(Sprite.tile))*16) + @as(u32,SpriteY) * 2 + 1]; 
    //                 const OBJPalette = self.pmem.grabPalette(if(self.Emu.CGBMode) Sprite.CGB_Palette else @as(u3,Sprite.Palette), false);
                    
    //                 const end:i32 = if (X2 + 8 > 159) 160-X2 else 8; // clamps right side of screen
    //                 var offset:u4 = 0;

    //                 while (offset < end): (offset += 1){
    //                     if(X2+@as(i32,@intCast(offset)) < 0) continue else X = @intCast(X2 + @as(i32,@intCast(offset))) ;// offscreen

    //                     const SpriteLoBit :u8 = (SpriteLo >> if(Sprite.XFlip) @truncate(offset) else @truncate(7 - offset)) & 1;
    //                     const SpriteHiBit :u8 = (SpriteHi >> if(Sprite.XFlip) @truncate(offset) else @truncate(7 - offset)) & 1;
    //                     const OBJIndex:u8 = (SpriteHiBit << 1 | SpriteLoBit);

    //                     if(self.Emu.CGBMode){
    //                         const ProrityBitmap :u3 = ((@as(u3,lcdc.BGWindowPriority)<<2)|(@as(u3,Sprite.Priority)<<1)|@as(u3,BGAttributeCache[X/8].Priority));

    //                         const BGPriority:bool = switch (ProrityBitmap) {
    //                             0b101 => (BGindexCache[X] != 0), // if BG color is 1-3 OBJ priority is false
    //                             0b110 => (BGindexCache[X] != 0),
    //                             0b111 => (BGindexCache[X] != 0),
    //                             else => false, // OBJ Wins
    //                         };

    //                         if(!BGPriority and OBJIndex != 0) self.LCD.PlacePixel(X, LY, OBJPalette[OBJIndex]); //self.screen[X][LY] = OBJPalette[OBJIndex];

    //                     }else{
    //                         if(OBJIndex != 0x00){

    //                             if(Sprite.Priority == 1){

    //                                 if(BGindexCache[X] == 0x00){
    //                                     self.LCD.PlacePixel(X, LY, OBJPalette[OBJIndex]);
    //                                     //self.screen[X][LY] = OBJPalette[OBJIndex]; 
    //                                 }
    //                             }
    //                             else{
    //                                 self.LCD.PlacePixel(X, LY, OBJPalette[OBJIndex]);
    //                                 //self.screen[X][LY] = OBJPalette[OBJIndex];
    //                             }
    //                         }
    //                     }
    //                 }
    //             }
    //         }
    //     }
    // }


    pub fn read(self : *PPU, address: u16) u8{

        return switch (address) {
            0xFF40 => @bitCast(self.regs.lcdc),
            0xFF41 => (@bitCast(self.regs.stat)),
            0xFF42 => self.regs.scy.get(),
            0xFF43 => self.regs.scx.get(),
            0xFF44 => self.regs.ly.get(),
            0xFF45 => self.regs.lyc.get(),
            0xFF46 => self.regs.dma.get(),
            0xFF47 => self.regs.bgp.get(),
            0xFF48 => self.regs.obp0.get(),
            0xFF49 => self.regs.obp1.get(),
            0xFF4A => self.regs.wy.get(),
            0xFF4B => self.regs.wx.get(),
            0xFF69 => self.pmem.readBG(self.mode), // BGPD
            0xFF6B => self.pmem.readOBJ(self.mode), // BGPD
            else => 0xFF,

        };

    }

    pub fn write(self : *PPU, address: u16,data: u8)void{

        switch (address) {
            0xFF40 => self.regs.lcdc = @bitCast(data),
            0xFF41 => self.regs.stat = @bitCast((@as(u8,@bitCast(self.regs.stat)) & 0x87) | (data & 0xF8)),
            0xFF42 => self.regs.scy.set(data),
            0xFF43 => self.regs.scx.set(data),
            // 0xFF44 is read only
            0xFF45 => self.regs.lyc.set(data),
            0xFF46 => {
                if(self.Emu.dma.OAMTransferInProgress) return;

                self.regs.dma.set(data);
                self.Emu.dma.StartOAMTransfer(data);
            },
            0xFF47 => {
                self.regs.bgp.set(data);
                if(self.Emu.CGBMode) return;
                self.pmem.updateDMGPalette(data,1);
            },
            0xFF48 => {
                self.regs.obp0.set(data);
                if(self.Emu.CGBMode) return;
                self.pmem.updateDMGPalette(data,2);
            },
            0xFF49 => {
                self.regs.obp1.set(data);
                if(self.Emu.CGBMode) return;
                self.pmem.updateDMGPalette(data,3);
            },
            0xFF4A => self.regs.wy.set(data),
            0xFF4B => self.regs.wx.set(data),
            0xFF68 => self.pmem.BCPS = @bitCast(data), 
            0xFF69 => self.pmem.writeBG(data,self.mode), 
            0xFF6A => self.pmem.OCPS = @bitCast(data), 
            0xFF6B => self.pmem.writeOBJ(data,self.mode),
            else => {},

        }
    }

    fn scanOAMCGB(self: *PPU) void {
        const ly : i16 = @intCast(self.regs.ly.get());
        const objHeight : i16 = if(self.regs.lcdc.OBJsize) 16 else 8;

        for(0..self.spriteCount) |sprite|{
            self.sprites[sprite] = 0xFF;
        }
        self.spriteCount = 0;

        var iter : i16 = 39;
        while (iter > -1) : (iter -= 1) {
            const entry = self.oam.Entries[@intCast(iter)];
            if(entry.Y < 1 or entry.Y > 159) continue; // if sprite is hidden no use checking it

    
            const SpriteY : i16 = @as(i16,@intCast(entry.Y)) - 16;
            if(ly >= SpriteY and ly < SpriteY + objHeight){
                self.sprites[self.spriteCount] = @intCast(iter);
                self.spriteCount += 1;
            }

            if(self.spriteCount == 10){
                return;
            }
        }
    }

    fn scanOAMDMG(self : *PPU) void {

        const ly : u8 = self.regs.ly.get();
        const ObjHeight: u8 = if(self.regs.lcdc.OBJsize) 16 else 8;

        // clear past sprites
        for(0..self.spriteCount)|i|{
            self.sprites[i] = 0xFF;
        }
        self.spriteCount = 0;

        // grab the indexes for visible sprites
        for(self.oam.Entries,0..) |entry,i|{
            
            if(entry.X != 0 and ly + 16 >= entry.Y and ly + 16 <= entry.Y + ObjHeight - 1){
                self.sprites[self.spriteCount] = i;
                self.spriteCount += 1;
            }
            // 10 sprites maximum
            if(self.spriteCount == 10){
                return;
            }
        }
    }

    fn compareLY_LYC (self: *PPU) void{

        self.regs.stat.LYCeqlLY = self.regs.ly.get() == self.regs.lyc.get();
        if(self.regs.stat.LYCeqlLY){
            // set LCD interrupt to true in the cpu
            self.Emu.cpu.regs.IF.setBit(1, 1);
        }
    }

};

pub const VRAM = struct {
    Banks : [2][0x2000]u8 = .{.{0}**0x2000}**2,
    CurrentBank : u8 = 0,

    pub fn read(self: *VRAM, address : u16)u8{
        return self.Banks[self.CurrentBank][address&0x1FFF];
    }

    pub fn write(self: *VRAM, address : u16, data: u8)void{
        self.Banks[self.CurrentBank][address&0x1FFF] = data;
    }
};

const Registers = struct {
    // PPU Register Set
    lcdc : LCDC = undefined,
    stat : STAT = undefined,
    scy  : Register = undefined,
    scx  : Register = undefined,
    ly   : Register = undefined,
    lyc  : Register = undefined,
    dma  : Register = undefined,
    bgp  : Register = undefined,
    obp0 : Register = undefined,
    obp1 : Register = undefined,
    wy   : Register = undefined,
    wx   : Register = undefined,

    /// CGB only regs
    

    pub fn init() Registers{
        var r = Registers{};

        r.lcdc = @bitCast(@as(u8,0x91));
        r.stat = @bitCast(@as(u8,0x80));
        r.scy.set(0x00);
        r.scx.set(0x00);
        r.lyc.set(0x00);
        r.dma.set(0x00);
        r.bgp.set(0xFC);
        r.wy.set(0x00);
        r.wx.set(0x00);

        return r;
    }
};

pub const OAM = struct {

    Entries : [40]OAMEntry = undefined,
    raw : [160]u8 = undefined,

    pub fn write(self:*OAM, Index : u16, data: u8)void{

        self.raw[Index] = data;

        self.Entries = @bitCast(self.raw);
    }

    pub fn read(self : *OAM, address : u16) u8{

        return self.raw[address-0xFE00];
    }
    
    
};

pub const OAMEntry = packed struct {
    Y : u8,
    X : u8,
    tile : u8,

    CGB_Palette : u3,
    Bank_No : u1,
    Palette : u1,
    XFlip : bool,
    YFlip : bool,
    Priority : u1,
};

const PaletteMemory = struct {

    
    BGPRAM  : [64]u8 = .{0} ** 64,
    OBJPRAM : [64]u8 = .{0} ** 64,
    BCPS : AddressFormat = @bitCast(@as(u8,0x00)),
    OCPS : AddressFormat = @bitCast(@as(u8,0x00)),

    const DMGPallete : [8]u8 = .{
        0xFF, 0xFF,
        0xB5, 0x56,
        0x4A, 0x29,
        0x00, 0x00,
    };


    pub fn readOBJ(self : *PaletteMemory,mode:PPUmodes)u8 {
        return if(mode != .DrawingPixels) self.OBJPRAM[self.OCPS.Address&0x3F] else 0xFF;
    }

    pub fn writeOBJ(self: *PaletteMemory,data:u8,mode:PPUmodes)void{
        if(mode != .DrawingPixels) self.OBJPRAM[self.OCPS.Address&0x3F] = data;
        if(self.OCPS.autoInc) self.OCPS.Address +%= 1;
    }

    pub fn readBG(self : *PaletteMemory,mode:PPUmodes)u8 {
        return if(mode != .DrawingPixels) self.BGPRAM[self.BCPS.Address&0x3F] else 0xFF;
    }

    pub fn writeBG(self: *PaletteMemory,data:u8,mode:PPUmodes)void{

        if(mode != .DrawingPixels) self.BGPRAM[self.BCPS.Address&0x3F] = data;
        if(self.BCPS.autoInc) self.BCPS.Address +%= 1;
    }

    pub fn grabPalette(self : *PaletteMemory, ID : u3, BG : bool)[4]u16{

        const Index : usize = (@as(u6,ID) * 8);

        var Out : [4]u16 = undefined;

        var i : usize = 0;
        while(i < 4) : (i += 1){
            Out[i] = if(BG) (@as(u16,self.BGPRAM[Index + (i*2) + 1]) << 8) | @as(u16,self.BGPRAM[Index + (i*2)]) else (@as(u16,self.OBJPRAM[Index + (i*2) + 1]) << 8 ) | @as(u16,self.OBJPRAM[Index + (i*2)]);
        }
        return Out;
    }

    /// input goes BGP OBJ0 OBJ1
    pub fn updateDMGPalette(self : *PaletteMemory, dmgPalette:u8, i : u2) void{
    
        
        const dmgArray: [4]u2 = .{ 
            @truncate(dmgPalette), 
            @truncate(dmgPalette >> 2), 
            @truncate(dmgPalette >> 4),
            @truncate(dmgPalette >> 6)
        };

        switch (i) {
            1 => {
                for(0..4) |ID|{
                    const IDcolorOffset = @as(u8,dmgArray[ID])*2;
                    const pOffset:u8 = @intCast(ID*2);
                    self.BGPRAM[pOffset] = DMGPallete[IDcolorOffset];
                    self.BGPRAM[pOffset+1] = DMGPallete[IDcolorOffset+1];
                }
                
            },
            2 =>{
                for(0..4) |ID|{
                    const IDcolorOffset = @as(u8,dmgArray[ID])*2;
                    const pOffset:u8 = @intCast(ID*2);
                    self.OBJPRAM[pOffset] = DMGPallete[IDcolorOffset];
                    self.OBJPRAM[pOffset+1] = DMGPallete[IDcolorOffset+1];
                }
            },
            3 =>{

                for(0..4) |ID|{
                    const IDcolorOffset = @as(u8,dmgArray[ID])*2;
                    const pOffset:u8 = @intCast(ID*2);
                    self.OBJPRAM[pOffset+8] = DMGPallete[IDcolorOffset];
                    self.OBJPRAM[pOffset+9] = DMGPallete[IDcolorOffset+1];
                }
            },
            else => unreachable,
        }
    }


    const AddressFormat = packed struct {
        Address : u6,
        padding : u1,
        autoInc : bool,
    };
    
};

pub const BGMapAtrributes = packed struct {
    ColorPalette : u3, // colors 1-3 of BG ar drawn over OBJ no matter what
    Bank : u1, // either bank 0 or bank 1
    pad : u1,
    XFlip : bool,
    Yflip : bool,
    Priority : u1, 
};

const LCDC = packed struct {
    BGWindowPriority : u1, // compatability mode-> windowBG blank CGB ->obj always over background
    OBJenable : bool,
    OBJsize : bool,
    BGtileMap : bool,
    BGWinTileData : bool,
    WindowEnable : bool,
    WindowTileMap : bool,
    LCDPPUEnable : bool,
};

const STAT = packed struct {
    PPUmode : PPUmodes,    // read only
    LYCeqlLY : bool, // read only
    Mode0Int : bool,
    Mode1Int : bool,
    Mode2Int : bool,
    LYCInt   : bool,
    empty    : u1,
};

const PPUmodes = enum(u2) {
    HBlank, // mode 0
    VBlank, // mode 1
    OAMScan, // mode 2
    DrawingPixels, // mode 3
};

const PixelFetcher = struct {

    ppu : *PPU,

    // BG-Window Vars
    BGFIFO : FIFO,
    BGmode : mode = .GetTile,

    tileMap : u16 = 0x9800,
    tileData : u16 = 0x9000,

    BGTileCounter : u8 = 0,
    WindowLineCounter : u8 = 0,

    tileX : u8 = undefined, // used for first tile so we dont push offscreen tiles 

    BGTileAddress : u16 = undefined,
    BGAttributes : BGMapAtrributes,
    BGLo : u8 = undefined,
    BGHi : u8 = undefined,

    // first tile fetch discards it
    firstTile : bool = true,

    //SpriteVars
    OBFIFO : FIFO,
    OBmode : mode = .GetTile,

    SpriteHeight: u8 = undefined,
    SpriteY:u8 = undefined,
    OBLo : u8 = undefined,
    OBHi : u8 = undefined,

    SpriteFetchOn: bool = false,

    CurSprite : OAMEntry = undefined,

    // General Vars

    PixelX : u8 = 0, // increments when we pop a pixel

    pub fn init(parent: *PPU,gpa :std.mem.Allocator)PixelFetcher{

        return PixelFetcher{
            .ppu = parent,
            .BGFIFO = .init(gpa),
            .OBFIFO = .init(gpa),
        };
    }

    pub fn ScanlineReset(self: *PixelFetcher) void{
        self.firstTile = true;
        self.PixelX = 0;

        // clear left over pixels
        self.BGFIFO.flush();
        self.OBFIFO.flush();
    }

    fn CheckSprites(self: *PixelFetcher)void{
        for(0..self.ppu.spriteCount) |spr|{
            if(self.ppu.sprites[spr] != 0xFF){
                if(self.ppu.oam.Entries[self.ppu.sprites[spr]].X <= self.PixelX){
                    self.CurSprite = self.ppu.oam.Entries[self.ppu.sprites[spr]];
                    self.ppu.sprites[spr] = 0xFF; // notfify that this sprite has been seen
                    self.BGmode = .GetTile;
                    self.OBmode = .GetTile;
                    self.SpriteFetchOn = true;
                }
            }
        }
    }

    // returns true when  we have reached the end of the screen
    pub fn tick(self : *PixelFetcher, dots : u32) bool{

        if(!self.SpriteFetchOn) self.CheckSprites();

        switch (self.OBmode) {
            .GetTile => {
                // already have tile in sprite attributes
                if(dots&3 != 0) return false;
                self.OBmode = .GetTileLo;
            },
            .GetTileLo =>{
                if(dots&3 != 0) return false;

                self.SpriteHeight = if(self.ppu.regs.lcdc.OBJsize) 16 else 8;
                const LY = self.ppu.regs.ly.get();
                self.SpriteY = if(self.CurSprite.YFlip) (self.SpriteHeight-1) - (LY + 16 - self.CurSprite.Y) else (LY + 16 - self.CurSprite.Y);

                self.OBLo = self.vram.Banks[if(self.Emu.CGBMode) self.CurSprite.Bank_No else 0][(@as(u32,(self.CurSprite.tile))*16) + @as(u32,self.SpriteY) * 2];
                self.OBmode = .GetTileHi;
            },
            .GetTileHi =>{
                if(dots&3 != 0) return false;
                self.OBHi = self.vram.Banks[if(self.Emu.CGBMode) self.CurSprite.Bank_No else 0][(@as(u32,(self.CurSprite.tile))*16) + @as(u32,self.SpriteY) * 2 + 1];
                
                self.OBmode = .push;
                self.CheckSprites(); // one last check
            },
            .push =>{
                
                const currentBit = if(self.CurSprite.X < 8) 8-self.CurSprite.X else 0;
                for(currentBit..8) |offset|{

                    if(self.PixelX + offset > 159) break; // clamp end
                    if(offset <= self.BGFIFO.len) continue; // discard pixel if that slot is already full
                    const SpriteLoBit :u8 = (self.OBLo >> if(self.CurSprite.XFlip) @truncate(offset) else @truncate(7 - offset)) & 1;
                    const SpriteHiBit :u8 = (self.OBLo >> if(self.CurSprite.XFlip) @truncate(offset) else @truncate(7 - offset)) & 1;
                    const OBJIndex:u8 = (SpriteHiBit << 1 | SpriteLoBit);

                    self.OBFIFO.enqueue(
                        Pixel{
                            .color = @truncate(OBJIndex),
                            .palette = if(self.ppu.Emu.CGBMode) self.CurSprite.CGB_Palette else @intCast(self.CurSprite.Palette),
                            .priority = self.CurSprite.Priority,
                        }
                    );

                }
                self.SpriteFetchOn = false;
                self.OBmode = .GetTile;
            },

        }
        switch (self.BGmode) {
            .GetTile => {
                const LY:u8 = self.regs.ly.get();
                const WY:u8 = self.regs.wy.get();
                const WX:u8 = self.regs.wx.get() -% 7;
                const scx:u8 = self.regs.scx.get();
                const scy:u8 = self.regs.scy.get();

                const lcdc = self.ppu.regs.lcdc; 

                var WindowTile:bool = false;
                    // Set up what maps and tile data to look at
                if(lcdc.WindowEnable and LY >= WY and self.PixelX >= WX){
                    WindowTile = true;
                    if(lcdc.WindowTileMap) self.tileMap = 0x9C00;

                }
                if(!WindowTile and lcdc.BGtileMap) self.tileMap = 0x9C00;
                if(lcdc.BGWinTileData) self.tileData = 0x8000;

                // initalize our Shifted Y and X position
                var y:u8 = 0;
                var x:u8 = self.PixelX;

                if(WindowTile) {x -%= WX; y = self.WindowLineCounter;} else {x +%= scx; y = scy +% LY;}
                //save x for push 
                self.tileX = x&7;
                // Now that we have our coords we can grab out tile index  and attributes
                const Tile_Attr_Address : u16 = @as(u16,self.tileMap-0x8000) + (@as(u16,y/8)*32) + (@as(u16,x/8));
                
                self.BGAttributes = @bitCast(self.vram.Banks[1][Tile_Attr_Address]);
                
                const tileIndex: u8 = self.vram.Banks[0][Tile_Attr_Address];
                
                const tileOffset: u16 = if (self.tileData == 0x8000)
                    @as(u16, tileIndex ) * 16 // unsigned
                else
                    @bitCast(@as(i16, @as(i8, @bitCast(tileIndex))) * 16); // signed, preserve sign when used as offset

                // Calculate yOffset with or without flip
                const yOffset: u16 = if(self.BGAttributes.Yflip and self.Emu.CGBMode) (7-(y&7))*2 else (y&7)*2;
                self.BGTileAddress = @as(u16,self.tileData - 0x8000) +% tileOffset +% yOffset;
                self.BGmode = .GetTileLo;
            },
            .GetTileLo =>{
                self.BGLo = self.vram.Banks[if(self.Emu.CGBMode) self.BGAttributes.Bank else 0][self.BGTileAddress];
                self.BGmode = .GetTileHi;
            },
            .GetTileHi =>{
                self.BGHi = self.vram.Banks[if(self.Emu.CGBMode) self.BGAttributes.Bank else 0][self.BGTileAddress + 1];
                self.BGmode = .push;
            },
            .push => blk :{

                if(self.BGFIFO.len != 0) break :blk; // if FIFO not empty dont push
                
                for(self.tileX..8) |offset|{

                    if(self.PixelX + offset > 159) break :blk; // clamps tiles to 

                    const BGLoBit :u8 = (self.BGLo >> if(self.BGAttributes.XFlip and self.ppu.Emu.CGBMode) @intCast(offset) else @intCast(7-offset)) & 1;
                    const BGHiBit :u8 = (self.BGHi >> if(self.BGAttributes.XFlip and self.ppu.Emu.CGBMode) @intCast(offset) else @intCast(7-offset)) & 1;
                    const BGindex : u8 = (BGHiBit << 1) | BGLoBit;
                    
                    self.BGFIFO.enqueue(
                        .{
                            .color = @truncate(BGindex),
                            .palette = if(self.ppu.Emu.CGBMode) self.BGAttributes.ColorPalette else 0,
                            .priority = self.BGAttributes.Priority,
                        }
                    );
                }

                self.BGmode = .GetTile;
                break :blk;
            },
        }

        // here we pop pixels to screen
        // only does anything if there is BG pixels
        if(self.BGFIFO.dequeue()) |bgPix|{

            const BGpallete = self.ppu.pmem.grabPalette(bgPix.palette, true);

            if(self.OBFIFO.dequeue()) |obPix|{
                const OBpalette = self.ppu.pmem.grabPalette(obPix.palette, false);
                if(self.ppu.Emu.CGBMode){

                    const PrioBitmap = (@as(u3,self.ppu.regs.lcdc.BGWindowPriority) << 2) | (@as(u3,obPix.priority) << 1) | (@as(u3,bgPix.priority));
                    const BGPriority:bool = switch (PrioBitmap) {
                        0b101 => (BGpallete[bgPix.color] != 0), // if BG color is 1-3 OBJ priority is false
                        0b110 => (BGpallete[bgPix.color] != 0),
                        0b111 => (BGpallete[bgPix.color] != 0),
                        else => false, // OBJ Wins
                    };

                    if(!BGPriority and obPix.color != 0) self.LCD.PlacePixel(self.PixelX, self.ppu.regs.ly.get(), OBpalette[obPix.color]);

                }else{
                    if(obPix.color != 0x00){

                        if(obPix.priority == 1){

                            if(bgPix.color == 0x00){
                                self.LCD.PlacePixel(self.PixelX, self.ppu.regs.ly.get(), OBpalette[obPix.color]);
                            }
                        }
                        else{
                            self.LCD.PlacePixel(self.PixelX, self.ppu.regs.ly.get(), OBpalette[obPix.color]);
                        }
                    }
                }

            }else{
                self.ppu.LCD.PlacePixel(self.PixelX, self.ppu.regs.ly.get(), BGpallete[bgPix.color]);
            }

            // increment our Pixel Position
            self.PixelX += 1;
            if(self.PixelX == 160) return true;
        }
        return false;
    }

    const mode = enum {
        GetTile,
        GetTileLo,
        GetTileHi,
        push,
    };

};

// essentially a queue
const FIFO = struct {
    const Node = struct {
        data : Pixel,
        next : ?*Node,
    };

    gpa : std.mem.Allocator,
    start : ?*Node,
    end : ?*Node,
    len :u8 = 0,

    pub fn init(gpa:std.mem.Allocator) FIFO{

        return FIFO{
            .gpa = gpa,
            .start = null,
            .end = null,
        };
    }
    pub fn enqueue(self: *FIFO, value : Pixel) !void{
        const node = try self.gpa.create(Node);
        node.* = .{.data = value, .next = null};
        if(self.end) |end| end.next = node
        else self.start = node;
        self.end = node;
        self.len += 1;
    }
    pub fn dequeue(self: *FIFO) ?Pixel{
        const start = self.start orelse return null;
        defer self.gpa.destroy(start);
        if(start.next) |next|{
            self.start = next;
        }else{
            self.start = null;
            self.end = null;
        }
        self.len -= 1;
        return start.data;

    }  

    // Dequeue until empty to deinitalize the Pixels
    pub fn flush(self : *FIFO)void{
        while(self.dequeue()) |pix|{
            _ = pix;
        }
    }
};

const Pixel = struct {
    color : u2,
    palette: u3,
    priority : u1,
};

test "FIFO"{
    var MyFetcher = PixelFetcher{
        .BGFIFO = .init(std.testing.allocator),
        .OBFIFO = .init(std.testing.allocator),
    };

   try MyFetcher.BGFIFO.enqueue(.{
    .color = 5,
    .palette = 10,
    .priority = 1,
   });

    try MyFetcher.BGFIFO.enqueue(.{
    .color = 1,
    .palette = 15,
    .priority = 0,
   });

    const myPixel : Pixel = MyFetcher.BGFIFO.dequeue() orelse Pixel{.color = 1,.palette = 1,.priority = 1};

    std.debug.print("Pixel Data :{x} {x} {x}\n", .{myPixel.color,myPixel.palette,myPixel.priority});
    const myPixel2 : Pixel = MyFetcher.BGFIFO.dequeue() orelse Pixel{.color = 1,.palette = 1,.priority = 1};

    std.debug.print("Pixel Data :{x} {x} {x}", .{myPixel2.color,myPixel2.palette,myPixel2.priority});
}


