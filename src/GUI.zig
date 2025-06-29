const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const ppu = @import("PPU.zig");
const c = @cImport({
    @cDefine("SDL_DISABLE_OLD_NAMES", {});
    @cInclude("SDL3/SDL.h");
    @cInclude("SDL3/SDL_revision.h");
    @cDefine("SDL_MAIN_HANDLED", {}); // We are providing our own entry point
    @cInclude("SDL3/SDL_main.h");
});

const WindowFlags : c.SDL_WindowFlags = c.SDL_WINDOW_RESIZABLE;

pub const GUI = struct {

    gbc : ?*GBC = null,

    window: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,

    surface : ?*c.SDL_Surface = null,
    texture : ?*c.SDL_Texture = null,

    var quit = false;

    pub fn init(name: [*:0]const u8, comptime w: c_int,comptime h:c_int) !GUI{
        if(!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL_Init_Failed;
        
        const win: ?*c.SDL_Window = c.SDL_CreateWindow(name, w, h, WindowFlags) orelse return error.WindowFailed;
        const ren: ?*c.SDL_Renderer = c.SDL_CreateRenderer(win, null) orelse return error.RendererFail;
        return GUI{
            .window = win.?,
            .renderer = ren.?,
            .surface = c.SDL_CreateSurface(160*4, 144*4, c.SDL_PIXELFORMAT_ABGR1555),
            .texture = c.SDL_CreateTexture(ren, c.SDL_PIXELFORMAT_ABGR1555,c.SDL_TEXTUREACCESS_TARGET,160*4,144*4),
        };
    }

    // This Function Runs te GUI and controlls the GBC
    pub fn Run(self : *GUI) !void{

        var ZigBoyColor = GBC{};
        self.gbc = &ZigBoyColor;

        //try self.gbc.?.init("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Legend of Zelda, The - Link's Awakening (U) (V1.2) [!].gb");
        //try self.gbc.?.init("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Pokemon Red (UE) [S][!].gb");
        //try self.gbc.?.init("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Pokemon - Silver Version (UE) [C][!].gbc");
        //try self.gbc.?.init("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/Pokemon - Crystal Version (USA, Europe) (Rev A).gbc");
        //try self.gbc.?.init("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/mem_timing.gb");
        try self.gbc.?.init("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/interrupt_time.gb");
        
        while(!quit){
            
            if(self.gbc) |ZBC|{
                ZBC.FrameFinished = false;
                ZBC.Run();
            }

            self.UpdateTexture();
            //self.UpdateBG();
            self.UpdateScreen();

            self.poll();
        }
        self.deinit();
    }

    fn UpdateScreen(self : *GUI)void{
        _ = c.SDL_SetRenderDrawColorFloat(self.renderer, 0, 0, 0, 0);
        _ = c.SDL_RenderClear(self.renderer);

        var w : f32 = 0;
        var h : f32 = 0;
        _ = c.SDL_GetTextureSize(self.texture.?, &w, &h);
        const rect = c.SDL_FRect{.x = 0, .y = 0 ,.h = h,.w = w,};

        _ = c.SDL_RenderTexture(self.renderer,self.texture, &rect,&rect);

        _ = c.SDL_RenderPresent(self.renderer); //updates the renderer
    }

    fn UpdateBG(self : *GUI) void{
        
        //const BG_Data_Start: u16 = 0x8000;
        const BG_Data_Start: u16 = 0x9000;

        const BG_Map_Start :u16 = 0x9800;
        //const BG_Map_Start :u16 = 0x9C00;

        // 32 By 32 Tile Map Made Up of Window and Background Tiles
        var y : c_int =0;
        while(y<32) : (y += 1)
        {   
            var x : c_int = 0;
            while(x<31) : (x += 1)
            {
                const Tile_Attr_Address: u16 = @as(u16,BG_Map_Start - 0x8000) + @as(u16,@intCast(x)) + @as(u16,@intCast(y*32));

                const BG_Attr : ppu.BGMapAtrributes = @bitCast(self.gbc.?.ppu.vram.Banks[1][Tile_Attr_Address]); 
                const tileIndex: u8 = self.gbc.?.ppu.vram.Banks[0][Tile_Attr_Address];
                
                const tileOffset: u16 = if (BG_Data_Start == 0x8000)
                    @as(u16, tileIndex ) * 16 // unsigned
                else
                    @bitCast(@as(i16, @as(i8, @bitCast(tileIndex))) * 16); // signed, preserve sign when used as offset

                const GBPallete = self.gbc.?.ppu.pmem.grabPalette(if(self.gbc.?.CGBMode) BG_Attr.ColorPalette else 0, true);

                for(0..8) |i|{
                    const lo = self.gbc.?.ppu.vram.Banks[if(self.gbc.?.CGBMode) BG_Attr.Bank else 0][(BG_Data_Start-0x8000) +% tileOffset + if(self.gbc.?.CGBMode and BG_Attr.Yflip) (7-i)*2 else  i*2];
                    const hi = self.gbc.?.ppu.vram.Banks[if(self.gbc.?.CGBMode) BG_Attr.Bank else 0][(BG_Data_Start-0x8000) +% tileOffset + if(self.gbc.?.CGBMode and BG_Attr.Yflip) (7-i)*2 + 1 else  i*2 + 1];
                    for(0..8) |j|{
                        const lo_bit = (lo >> if(self.gbc.?.CGBMode and BG_Attr.XFlip) @truncate(j) else @truncate(7-j))&1;
                        const hi_bit = (hi >> if(self.gbc.?.CGBMode and BG_Attr.XFlip) @truncate(j) else @truncate(7-j))&1;

                        const BG_Index = (hi_bit << 1) | lo_bit;

                        const rect : c.SDL_Rect = .{
                            .x = (x*8 + @as(c_int,@intCast(j)))*4,
                            .y = (y*8 + @as(c_int,@intCast(i)))*4,
                            .w = 4,
                            .h = 4,
                        };

                        _= c.SDL_FillSurfaceRect(self.surface, &rect, @byteSwap(GBPallete[BG_Index]) | 0x8000);


                    }
                }
            } 
        }

        //Update texture with surface
        _ = c.SDL_UpdateTexture(self.texture, null, self.surface.?.pixels, self.surface.?.pitch);
    }

    fn UpdateTexture(self : *GUI) void{

        const surface = self.surface.?; // or your SDL_Surface pointer
        const pixels: [*]u16 = @ptrCast(@alignCast(surface.pixels));
        const pitch = @divFloor(surface.pitch, 2); // pitch is in bytes, divide by 2 for u16

        var x : usize = 0;
        while(x < 160) : (x +%=1){
            var y : usize = 0;
            while(y < 144) : (y +%=1){

                const color: u16 = if(self.gbc) |ZBC| ZBC.ppu.screen[x][y] else 0;
                for(0..4) |dy|{
                    for(0..4) |dx|{
                        pixels[(y*4 + dy) * @as(usize,(@intCast(pitch))) + (x*4 + dx)] = color | 0x8000;
                    }
                }
            }
        }    
        
        _ = c.SDL_UpdateTexture(self.texture, null, self.surface.?.pixels, self.surface.?.pitch);
    }

    pub fn deinit(self : *GUI)void{

        self.gbc.?.deinit();

        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroySurface(self.surface);
        c.SDL_DestroyTexture(self.texture);
        c.SDL_Quit();
    }

    fn poll(self : *GUI) void {
        var e : c.SDL_Event = undefined;

        while(c.SDL_WaitEventTimeout(&e, 2)){
            switch (e.type) {
                c.SDL_EVENT_QUIT => {
                    if(self.gbc) |ZBC| ZBC.FrameFinished = true;
                    quit = true;
                },
                c.SDL_EVENT_KEY_DOWN=>{
                    switch (e.key.scancode) {
                        c.SDL_SCANCODE_W => self.gbc.?.bus.io.joypad.pressKey(2),
                        c.SDL_SCANCODE_A => self.gbc.?.bus.io.joypad.pressKey(1),
                        c.SDL_SCANCODE_S => self.gbc.?.bus.io.joypad.pressKey(3),
                        c.SDL_SCANCODE_D => self.gbc.?.bus.io.joypad.pressKey(0),
                        c.SDL_SCANCODE_O => self.gbc.?.bus.io.joypad.pressKey(7),
                        c.SDL_SCANCODE_P => self.gbc.?.bus.io.joypad.pressKey(6),
                        c.SDL_SCANCODE_K => self.gbc.?.bus.io.joypad.pressKey(5),
                        c.SDL_SCANCODE_L => self.gbc.?.bus.io.joypad.pressKey(4),
                        else =>{},
                    }
                },
                c.SDL_EVENT_KEY_UP => {
                    switch (e.key.scancode) {
                        c.SDL_SCANCODE_W => self.gbc.?.bus.io.joypad.releaseKey(2),
                        c.SDL_SCANCODE_A => self.gbc.?.bus.io.joypad.releaseKey(1),
                        c.SDL_SCANCODE_S => self.gbc.?.bus.io.joypad.releaseKey(3),
                        c.SDL_SCANCODE_D => self.gbc.?.bus.io.joypad.releaseKey(0),
                        c.SDL_SCANCODE_O => self.gbc.?.bus.io.joypad.releaseKey(7),
                        c.SDL_SCANCODE_P => self.gbc.?.bus.io.joypad.releaseKey(6),
                        c.SDL_SCANCODE_K => self.gbc.?.bus.io.joypad.releaseKey(5),
                        c.SDL_SCANCODE_L => self.gbc.?.bus.io.joypad.releaseKey(4),
                        else => {},
                    }
                },
                else => {},
            }
        }
    }
};

test "Check CGB Mode" {
    var Zigboy = GBC{};
    try Zigboy.init("C:/Users/reece/Documents/Coding/Repos/ZigBoyColor/Roms/02-interrupts.gb");

    std.debug.print("CGB Mode : {}", .{Zigboy.CGBMode});
    try std.testing.expect(Zigboy.CGBMode);


    Zigboy.deinit();
}