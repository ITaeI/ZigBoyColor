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
    TextureViewport : c.SDL_FRect = undefined,

    const allocator = std.heap.page_allocator;
    var quit = false;
    const pixelScale = 4;

    pub fn init(name: [*:0]const u8, comptime w: c_int,comptime h:c_int) !GUI{
        if(!c.SDL_Init(c.SDL_INIT_VIDEO)) return error.SDL_Init_Failed;
        
        const win: ?*c.SDL_Window = c.SDL_CreateWindow(name, w, h, WindowFlags) orelse return error.WindowFailed;
        const ren: ?*c.SDL_Renderer = c.SDL_CreateRenderer(win, null) orelse return error.RendererFail;
        return GUI{
            .window = win.?,
            .renderer = ren.?,
            .surface = c.SDL_CreateSurface(160*pixelScale, 144*pixelScale, c.SDL_PIXELFORMAT_ABGR1555),
            .texture = c.SDL_CreateTexture(ren, c.SDL_PIXELFORMAT_ABGR1555,c.SDL_TEXTUREACCESS_TARGET,160*pixelScale,144*pixelScale),
            .TextureViewport = .{.x=0,.y=0,.w=w,.h=h}
        };
    }

    // This Function Runs te GUI and controlls the GBC
    pub fn Run(self : *GUI) !void{

        try self.loadRom("Roms/Pokemon - Yellow Version (USA, Europe).gbc");
        //try self.loadRom("Roms/Pokemon - Crystal Version (USA, Europe) (Rev A).gbc");
        //try self.loadRom("Roms/Pokemon Red (UE) [S][!].gb");
        //try self.loadRom("Roms/Pokemon - Silver Version (UE) [C][!].gbc");
        //try self.loadRom("Roms/Legend of Zelda, The - Link's Awakening DX (USA, Europe).gbc");
        //try self.loadRom("Roms/Legend of Zelda, The - Oracle of Ages (USA).gbc");
        //try self.loadRom("Roms/Dragon Warrior III (U) [C][!].gbc");
        //try self.loadRom("Roms/interrupt_time.gb");

        // Color Tests

        //try self.loadRom("Roms/bg_oam_priority.gbc"); // failed :(
        //try self.loadRom("Roms/hblank_vram_dma.gbc"); // passed
        //try self.loadRom("Roms/oam_internal_priority.gbc"); //passed
        //try self.loadRom("Roms/mbc_oob_sram_mbc1.gbc"); // passed
        //try self.loadRom("Roms/mbc_oob_sram_mbc3.gbc");
        //try self.loadRom("Roms/mbc_oob_sram_mbc5.gbc");
        //try self.loadRom("Roms/ppu_disabled_state.gbc"); //passed

        //c.SDL_ShowOpenFileDialog(SDL_DialogFileCallback callback, void *userdata, SDL_Window *window, const SDL_DialogFileFilter *filters, int nfilters, const char *default_location, bool allow_many);
        while(!quit){
            
            if(self.gbc) |ZBC|{
                ZBC.FrameFinished = false;
                ZBC.Run();
            }

            self.UpdateScreen();

            self.poll();
        }
        // Lastly destroy textures emulator core and quit!!
        self.deinit();
    }

    fn UpdateScreen(self : *GUI)void{
        _ = c.SDL_SetRenderDrawColorFloat(self.renderer, 0, 0, 0, 0);
        _ = c.SDL_RenderClear(self.renderer);

        _ = c.SDL_UpdateTexture(self.texture, null, self.surface.?.pixels, self.surface.?.pitch);
        _ = c.SDL_RenderTexture(self.renderer,self.texture, null,&self.TextureViewport);

        _ = c.SDL_RenderPresent(self.renderer); //updates the renderer
    }

    fn updateViewPort(self : *GUI, w: c_int, h: c_int) void{

        // viewport size
        const AspectRatio: f32 = @as(f32,160)/@as(f32,144);
        var ViewWidth : f32 = @floatFromInt(w);
        var ViewHeight : f32 = ViewWidth/AspectRatio;

        if(ViewHeight > @as(f32,@floatFromInt(h))){
            ViewHeight = @floatFromInt(h);
            ViewWidth = ViewHeight*AspectRatio;
        }

        
        self.TextureViewport = c.SDL_FRect{
            .x = (@as(f32,@floatFromInt(w))*0.5 - ViewWidth*0.5),
            .y = (@as(f32,@floatFromInt(h))*0.5 - ViewHeight*0.5),
            .w = ViewWidth,
            .h = ViewHeight,
        };
    }

    // fn UpdateBG(self : *GUI) void{
        
    //     //const BG_Data_Start: u16 = 0x8000;
    //     const BG_Data_Start: u16 = 0x9000;

    //     const BG_Map_Start :u16 = 0x9800;
    //     //const BG_Map_Start :u16 = 0x9C00;

    //     // 32 By 32 Tile Map Made Up of Window and Background Tiles
    //     var y : c_int =0;
    //     while(y<32) : (y += 1)
    //     {   
    //         var x : c_int = 0;
    //         while(x<31) : (x += 1)
    //         {
    //             const Tile_Attr_Address: u16 = @as(u16,BG_Map_Start - 0x8000) + @as(u16,@intCast(x)) + @as(u16,@intCast(y*32));

    //             const BG_Attr : ppu.BGMapAtrributes = @bitCast(self.gbc.?.ppu.vram.Banks[1][Tile_Attr_Address]); 
    //             const tileIndex: u8 = self.gbc.?.ppu.vram.Banks[0][Tile_Attr_Address];
                
    //             const tileOffset: u16 = if (BG_Data_Start == 0x8000)
    //                 @as(u16, tileIndex ) * 16 // unsigned
    //             else
    //                 @bitCast(@as(i16, @as(i8, @bitCast(tileIndex))) * 16); // signed, preserve sign when used as offset

    //             const GBPallete = self.gbc.?.ppu.pmem.grabPalette(if(self.gbc.?.CGBMode) BG_Attr.ColorPalette else 0, true);

    //             for(0..8) |i|{
    //                 const lo = self.gbc.?.ppu.vram.Banks[if(self.gbc.?.CGBMode) BG_Attr.Bank else 0][(BG_Data_Start-0x8000) +% tileOffset + if(self.gbc.?.CGBMode and BG_Attr.Yflip) (7-i)*2 else  i*2];
    //                 const hi = self.gbc.?.ppu.vram.Banks[if(self.gbc.?.CGBMode) BG_Attr.Bank else 0][(BG_Data_Start-0x8000) +% tileOffset + if(self.gbc.?.CGBMode and BG_Attr.Yflip) (7-i)*2 + 1 else  i*2 + 1];
    //                 for(0..8) |j|{
    //                     const lo_bit = (lo >> if(self.gbc.?.CGBMode and BG_Attr.XFlip) @truncate(j) else @truncate(7-j))&1;
    //                     const hi_bit = (hi >> if(self.gbc.?.CGBMode and BG_Attr.XFlip) @truncate(j) else @truncate(7-j))&1;

    //                     const BG_Index = (hi_bit << 1) | lo_bit;

    //                     const rect : c.SDL_Rect = .{
    //                         .x = (x*8 + @as(c_int,@intCast(j)))*4,
    //                         .y = (y*8 + @as(c_int,@intCast(i)))*4,
    //                         .w = 4,
    //                         .h = 4,
    //                     };

    //                     _= c.SDL_FillSurfaceRect(self.surface, &rect, @byteSwap(GBPallete[BG_Index]) | 0x8000);


    //                 }
    //             }
    //         } 
    //     }

    //     //Update texture with surface
    //     _ = c.SDL_UpdateTexture(self.texture, null, self.surface.?.pixels, self.surface.?.pitch);
    // }

    fn loadRom(self :*GUI, file: []const u8) !void{
        if(self.gbc) |gbc|{
            gbc.deinit();
            allocator.destroy(gbc);
        }

        self.gbc = allocator.create(GBC) catch return;
        try self.gbc.?.init(self,file);
    }

    pub fn PlacePixel(self : *GUI, x : u8, y:u8, color : u16) void{

        const surface = self.surface.?; // or your SDL_Surface pointer
        const pixels: [*]u16 = @ptrCast(@alignCast(surface.pixels));
        const pitch = @divFloor(surface.pitch, 2); // pitch is in bytes, divide by 2 for u16

        for(0..pixelScale)|dy|{
            for(0..pixelScale)|dx|{
                pixels[(@as(usize,y)*pixelScale + dy) * @as(usize,(@intCast(pitch))) + (@as(usize,x)*pixelScale + dx)]  = color | 0x8000;
            }
        }
    }

    pub fn deinit(self : *GUI)void{

        // deinit the GBC and destroy it
        if(self.gbc) |gbc| {
            gbc.deinit();
            allocator.destroy(gbc);
        }

        // destroy image ptrs
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
                    quit = true;
                },
                c.SDL_EVENT_KEY_DOWN=>{
                    switch (e.key.scancode) {
                        c.SDL_SCANCODE_W => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(2),
                        c.SDL_SCANCODE_A => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(1),
                        c.SDL_SCANCODE_S => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(3),
                        c.SDL_SCANCODE_D => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(0),
                        c.SDL_SCANCODE_O => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(7),
                        c.SDL_SCANCODE_P => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(6),
                        c.SDL_SCANCODE_K => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(5),
                        c.SDL_SCANCODE_L => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(4),
                        //c.SDL_SCANCODE_N => self.loadRom(),
                        else =>{},
                    }
                },
                c.SDL_EVENT_KEY_UP => {
                    switch (e.key.scancode) {
                        c.SDL_SCANCODE_W => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(2),
                        c.SDL_SCANCODE_A => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(1),
                        c.SDL_SCANCODE_S => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(3),
                        c.SDL_SCANCODE_D => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(0),
                        c.SDL_SCANCODE_O => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(7),
                        c.SDL_SCANCODE_P => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(6),
                        c.SDL_SCANCODE_K => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(5),
                        c.SDL_SCANCODE_L => if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(4),
                        else => {},
                    }
                },
                c.SDL_EVENT_WINDOW_RESIZED =>{
                    var w: c_int = 0;
                    var h: c_int = 0;

                    _ = c.SDL_GetWindowSize(self.window,&w,&h);

                    if(w < 640) w = 640;
                    if(h < 576) h = 576;

                    _ = c.SDL_SetWindowSize(self.window,w,h);

                    self.updateViewPort(w, h);
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