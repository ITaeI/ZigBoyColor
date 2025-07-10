const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const ppu = @import("PPU.zig");
const rl = @import("raylib");
const rg = @import("raygui");

pub const GUI = struct {

    gbc : ?*GBC = null,
    CGBimage : rl.Image = undefined,
    CGBtexture : rl.Texture2D = undefined,

    // viewport components
    Src : rl.Rectangle = .{.x = 0,.y = 0,.width = CGBwidth,.height = CGBheight},
    Dest : rl.Rectangle = .{.x = 0,.y = 0,.width = 640,.height = 576},

    FB : FileBrowser = undefined,
    FBalloc : std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}){},

    const CGBheight = 144;
    const CGBwidth = 160;
    const CGBalloc = std.heap.page_allocator;

    pub fn init(self: *GUI,Name : [:0]const u8, w:comptime_int,h:comptime_int) !void{
        rl.setConfigFlags(.{.window_resizable = true});
        rl.initWindow(w, h, Name);
        rl.setWindowMinSize(w, h);
        rl.setTargetFPS(60);

        const icon = try rl.loadImage("assets/GBCIcon.png");
        rl.setWindowIcon(icon);
        rl.unloadImage(icon);

        styleGUI();

        self.CGBimage = rl.genImageColor(160, 144, .black);
        self.CGBtexture = try rl.loadTextureFromImage(self.CGBimage);
        self.FB = .init(self,self.FBalloc.allocator());
    }   

    fn styleGUI()void{
        rg.setStyle(.default, .{ .default = .text_size }, 22);
    }

    pub fn Run(self : *GUI) void{
        //self.loadRom("Roms/Pokemon - Yellow Version (USA, Europe).gbc");
        //try self.loadRom("Roms/Pokemon - Crystal Version (USA, Europe) (Rev A).gbc");
        // try self.loadRom("Roms/Pokemon Red (UE) [S][!].gb");
        //try self.loadRom("Roms/Pokemon - Silver Version (UE) [C][!].gbc");
        // try self.loadRom("Roms/Legend of Zelda, The - Link's Awakening DX (USA, Europe).gbc");
        //try self.loadRom("Roms/Legend of Zelda, The - Oracle of Ages (USA).gbc");
        //try self.loadRom("Roms/Dragon Warrior III (U) [C][!].gbc");
        // try self.loadRom("Roms/Dragon Quest Monsters (G) [C][!].gbc");
        // try self.loadRom("Roms/Harvest Moon GB (U) [C][!].gbc");

        //try self.loadRom("Roms/Super Mario Bros. Deluxe (USA, Europe).gbc");
        // try self.loadRom("Roms/interrupt_time.gb"); // Wierd infinite loop
        // try self.loadRom("Roms/Wario Land 3 (World) (En,Ja).gbc");

        //Color Tests

        // try self.loadRom("Roms/bg_oam_priority.gbc"); // failed :(
        // try self.loadRom("Roms/hblank_vram_dma.gbc"); // passed
        // try self.loadRom("Roms/oam_internal_priority.gbc"); //passed
        // try self.loadRom("Roms/mbc_oob_sram_mbc1.gbc"); // passed
        // try self.loadRom("Roms/mbc_oob_sram_mbc3.gbc");
        // try self.loadRom("Roms/mbc_oob_sram_mbc5.gbc");
        // try self.loadRom("Roms/ppu_disabled_state.gbc"); //passed

        while (!rl.windowShouldClose()) {

            if(self.gbc) |ZigBoyColor|{
                ZigBoyColor.FrameFinished = false;
                ZigBoyColor.Run();
            }

            self.updateScreen();
        }
        self.deinit();
    }

    fn updateScreen(self: *GUI)void{
        // Update Input and Viewport
        rl.updateTexture(self.CGBtexture, self.CGBimage.data);
        self.UpdateViewPort();
        self.checkInputs();

        rl.beginDrawing();
        defer rl.endDrawing();        
        
        // Draw
        rl.clearBackground(.black);
        rl.drawTexturePro(self.CGBtexture, self.Src, self.Dest, rl.Vector2{.x = 0,.y = 0}, 0, .white);
        self.FB.Show();
    }

    fn UpdateViewPort (self : *GUI)void{
        const ScreenWidth:f32 = @floatFromInt(rl.getScreenWidth());
        const ScreenHeight:f32 = @floatFromInt(rl.getScreenHeight());

        const aspRatio:f32 = 144.0/160.0;

        // Grow along with Screen
        self.Dest.width = ScreenWidth;
        if(ScreenWidth * aspRatio > ScreenHeight){
            self.Dest.width = ScreenHeight/aspRatio;
            self.Dest.height = ScreenHeight;
        }else self.Dest.height = ScreenWidth*aspRatio;

        // Center Screen
        self.Dest.x = (ScreenWidth - self.Dest.width)/2;
        self.Dest.y = (ScreenHeight - self.Dest.height)/2;

    }

    fn checkInputs(self : *GUI)void{

        const KeyCodes: [8]rl.KeyboardKey = .{.d,.a,.w,.s,.l,.k,.p,.o};
        for (KeyCodes,0..) |key,i|{
            if(rl.isKeyReleased(key)) if(self.gbc) |gbc| gbc.bus.io.joypad.releaseKey(@truncate(i));
        }

        var KeyPressed = rl.getKeyPressed();
        while(KeyPressed != .null) : (KeyPressed = rl.getKeyPressed()){
            switch (KeyPressed) {
                .w => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(2),
                .a => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(1),
                .s => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(3),
                .d => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(0),
                .o => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(7),
                .p => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(6),
                .k => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(5),
                .l => if(self.gbc) |gbc| gbc.bus.io.joypad.pressKey(4),
                else => {},
            }
        }
    }

    fn loadRom(self :*GUI, file: []const u8) void{

        self.ExitEmulator();

        self.gbc = CGBalloc.create(GBC) catch return;
        self.gbc.?.init(self,file) catch self.ExitEmulator();
    }

    pub fn ExitEmulator(self : *GUI)void{
        if(self.gbc) |gbc|{
            gbc.deinit();
            CGBalloc.destroy(gbc);
            self.gbc = null;
        }
    }

    pub fn PlacePixel(self : *GUI, x : u8, y:u8, color : u16) void{
        rl.imageDrawPixel(&self.CGBimage, @intCast(x), @intCast(y), 

        rl.Color{
            .a = 255,
            .r = formatColor(color,1),
            .g = formatColor(color,2),
            .b = formatColor(color,3),
        });
    }

    fn deinit(self : *GUI)void{
        // deinit the GBC and destroy it
        self.ExitEmulator();
        self.FB.deinit();
        _ = self.FBalloc.deinit();
        rl.unloadTexture(self.CGBtexture);
        rl.closeWindow();
    }
};

/// components 1-r, 2-g, 3-b
fn formatColor(color : u16, component:u3)u8{
    return switch (component) {
        1 =>{
            const r5:u8 = @truncate((color)&0x1F);
            return (r5<<3)|(r5>>2);
        },
        2 =>{
            const g5:u8 = @truncate((color>>5)&0x1F);
            return (g5<<3)|(g5>>2);
        },
        3 =>{
            const b5:u8 = @truncate((color>>10)&0x1F);
            return (b5<<3)|(b5>>2);
        },
        else =>unreachable,
    };
}

const FileBrowser = struct {

    gui : *GUI = undefined,
    Files : std.ArrayList([]const u8) = undefined,
    alloc : std.mem.Allocator = undefined,

    windowRect : rl.Rectangle = .init(0, 0, 640,576),
    fileButtonRect : rl.Rectangle = .init(10, 25, 40, 20),

    visible:bool = true,

    pub fn init(parent : *GUI,alloc: std.mem.Allocator) FileBrowser{
        var fb = FileBrowser{};
        fb.Files = std.ArrayList([]const u8).init(alloc);
        fb.alloc = alloc;
        fb.gui = parent;
        return fb;
    }

    pub fn deinit(self : *FileBrowser) void{
        self.Files.deinit();
    }

    pub fn Show(self : *FileBrowser)void{
        if(!self.visible) return;

        if (rg.windowBox(self.windowRect, "Select Rom") == 1) self.visible = false;

        _ = rg.panel(rl.Rectangle.init(0, 50, 640, 300), "My Panel");

        // working prototype for now
        // will create a file system browser to look for other games
        if(rg.labelButton(self.fileButtonRect, "Roms/Pokemon - Yellow Version (USA, Europe).gbc")){
           self.gui.loadRom("Roms/Pokemon - Yellow Version (USA, Europe).gbc");
           self.visible = false;
        
        }
    }
};