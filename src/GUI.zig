const std = @import("std");
const GBC = @import("GBC.zig").GBC;
const ppu = @import("PPU.zig");
const rl = @import("raylib");
const cl = @import("zclay");
const renderer = @import("renderer/raylib_clay.zig");

// const ColorPallette = [_]cl.Color{
//     cl.Color{8, 24, 32,255}, //Black
//     cl.Color{52, 104, 86,255}, // Dark Gray
//     cl.Color{136, 192, 112,255}, // light Gray
//     cl.Color{224, 248, 208,255}, // White
// };

const ColorPallette = [_]cl.Color{
    cl.Color{15, 56, 15, 255},
    cl.Color{48, 98, 48, 255},
    cl.Color{139, 172, 15, 255},
    cl.Color{155, 188, 15, 255},
};

var GBPaletteIndex :usize  = 6;

fn UpdatePalette(index : usize)void{
  GBPaletteIndex = index;

  Black = GBCPalettes[index][0];
  DarkGray = GBCPalettes[index][1];
  LightGray = GBCPalettes[index][2];
  White = GBCPalettes[index][3];  
}

const PaletteNames = [_][]const u8{
    "DMG Grayscale",
    "Classic GameBoy",
    "Sepia",
    "Blue",
    "Red",
    "Orange",
    "Purple",
};

var Black : cl.Color = GBCPalettes[6][0];
var DarkGray : cl.Color = GBCPalettes[6][1];
var LightGray : cl.Color = GBCPalettes[6][2];
var White : cl.Color = GBCPalettes[6][3];

const GBCPalettes = [_][4]cl.Color{
    // DMG (Original Game Boy grayscale)
    .{
        cl.Color{15, 15, 15, 255},    // Darkest
        cl.Color{85, 85, 85, 255},    // Dark
        cl.Color{170, 170, 170, 255}, // Light
        cl.Color{255, 255, 255, 255}, // Lightest
    },
    // Greenish (classic Game Boy)
    .{
        cl.Color{15, 56, 15, 255},
        cl.Color{48, 98, 48, 255},
        cl.Color{139, 172, 15, 255},
        cl.Color{155, 188, 15, 255},
    },
    // Sepia
    .{
        cl.Color{40, 24, 8, 255},
        cl.Color{96, 56, 24, 255},
        cl.Color{176, 112, 56, 255},
        cl.Color{224, 192, 128, 255},
    },
    // Blue
    .{
        cl.Color{8, 24, 48, 255},
        cl.Color{52, 104, 130, 255},
        cl.Color{136, 192, 224, 255},
        cl.Color{178, 208, 248, 255},
    },
    // Red
    .{
        cl.Color{32, 8, 8, 255},
        cl.Color{104, 52, 52, 255},
        cl.Color{192, 112, 112, 255},
        cl.Color{248, 208, 208, 255},
    },
    // Orange
    .{
        cl.Color{32, 24, 8, 255},
        cl.Color{104, 86, 52, 255},
        cl.Color{192, 160, 112, 255},
        cl.Color{248, 224, 208, 255},
    },
    // Purple
    .{
        cl.Color{24, 8, 32, 255},
        cl.Color{86, 52, 104, 255},
        cl.Color{160, 112, 192, 255},
        cl.Color{224, 208, 248, 255},
    },
};

const HeaderFontSize = 48;
const FontSize = 32;

pub const GUI = struct {

    // Gameboy Color Pointer
    gbc : ?*GBC = null,

    // Raylib Renderer
    CGBimage : rl.Image = undefined,
    CGBtexture : rl.Texture2D = undefined,

    // Clay Specific Items
    ClayMem: []u8 = undefined,
    MinClayMem:u32 = undefined,
    MouseClicked : bool = false,

    // Window Showing Bools
    showFileBrowser : bool = false,
    showFileDropdown : bool = false,
    showViewDropdown : bool = false,
    showSettings : bool = false,

    // Window Control Bools
    Exit : bool = false,

    // file Specific Items
    cwd : []const u8 = "Empty",
    PathAllocated : bool = false,
    SelectedRom : []const u8 = "Please Select A Rom",
    LoadedRom : []const u8 = "None",
    RomList : std.ArrayList(std.fs.Dir.Entry) = undefined,

    // Allocators
    pageAlloc: std.mem.Allocator = std.heap.page_allocator,
    gpa : std.heap.GeneralPurposeAllocator(.{}) = std.heap.GeneralPurposeAllocator(.{}).init,


    pub fn init(self: *GUI,Name : [:0]const u8, w:comptime_int,h:comptime_int) !void{
        
        // Initialize Clay
        self.MinClayMem = cl.minMemorySize();
        self.ClayMem = try self.pageAlloc.alloc(u8, self.MinClayMem);

        const arena : cl.Arena = cl.createArenaWithCapacityAndMemory(self.ClayMem);
        _ = cl.initialize(arena, .{.h = h,.w = w}, .{});
        cl.setMeasureTextFunction(void, {},renderer.measureText);
        
        // Initialize Raylib
        rl.setConfigFlags(.{.window_resizable = true});
        rl.initWindow(w, h, Name);
        rl.setWindowMinSize(w, h);
        rl.setTargetFPS(60);
        rl.setExitKey(.null);

        const icon = try rl.loadImage("assets/GBCIcon.png");
        rl.setWindowIcon(icon);
        rl.unloadImage(icon);

        // create our image and texture
        self.CGBimage = rl.genImageColor(160, 144, .black);
        self.CGBtexture = try rl.loadTextureFromImage(self.CGBimage);

        // Initialize our File List and directory
        self.cwd = @ptrCast(rl.getWorkingDirectory());
        self.RomList = .init(self.gpa.allocator());
        try self.scanDir();

        // fonts
        //renderer.raylib_fonts[0] = try rl.loadFont("PressStart2P-vaV7.ttf");
        renderer.raylib_fonts[0] = try rl.loadFont("assets/Tanker-Regular.ttf");
    }   

    pub fn Run(self : *GUI) !void{

        while (!rl.windowShouldClose() and !self.Exit) {

            if(self.gbc) |ZigBoyColor|{
                ZigBoyColor.FrameFinished = false;
                ZigBoyColor.Run();
            }

            rl.beginDrawing();
            defer rl.endDrawing();        
            
            // Draw
            rl.clearBackground(.black);
            rl.updateTexture(self.CGBtexture, self.CGBimage.data);

            // lastly we render our gui
            try renderer.clayRaylibRender(self.DrawGui(), self.gpa.allocator()); 
            self.checkInputs(); 
        }
        self.deinit();
    }

    fn DrawGui(self : *GUI) []cl.RenderCommand{

        UpdateWindowSize();
        self.UpdateMouse();

        cl.beginLayout();

        cl.UI()(.{
            .id = .ID("Outer Container"),
            .layout = .{
                .sizing = .grow, 
                .direction = .top_to_bottom,
                .padding = .all(8),
                .child_gap = 8
            },
            .background_color = Black,
        })({
            self.TabBar();

            cl.UI()(.{
                .id = .ID("LowerContent"),
                .layout = .{
                    .sizing = .{.h = .grow, .w = .grow},
                    .direction = .left_to_right,
                    .child_gap = 16,
                }
            })({
                if(self.showFileBrowser) self.FilePicker();
                if(self.showSettings) self.Settings();
                self.GBCscreen();
            });

        });
        return cl.endLayout();
    }
    // Main Content Functions
    fn Settings(_ : *GUI)void{

        cl.UI()(.{
            .id = .ID("Settings Page"),
            .layout = .{
                .sizing = .{.w = .percent(0.33), .h = .grow},
                .direction = .top_to_bottom,
                .child_gap = 8,
                .child_alignment = .{.x = .left, .y = .top},
                .padding = .{.left = 12, .right = 8, .top = 8,.bottom = 8},
            },

            // We need to clip this so that we can scroll through files
            .clip = .{.vertical = true, .child_offset = cl.getScrollOffset()},
            .corner_radius = .all(10),
            .background_color = White,
            .border = .{
                .width = .{.left = 5, .right = 5,.top = 5,.bottom = 5},
                .color = DarkGray,
            }
        })({ 
            Header("GameBoy Settings");

            for(PaletteNames,0..) |paletteName,i|{

                cl.UI()(.{
                    .layout = .{
                        .sizing = .{.w = .grow,.h = .fit},
                        .direction = .left_to_right,
                        .child_gap = 8,
                        .child_alignment = .{.x = .left ,.y = .center},
                        .padding = .{.right = 8}
                    }
                })({
                    cl.UI()(.{
                        .id = .ID(paletteName),
                        .layout = .{
                            .sizing = .{.h = .fit,.w = .grow},
                            .child_alignment = .{.x = .left,.y = .center},
                            .padding = .{.left = 8, .right = 8, .top = 2,.bottom = 2},
                        },
                        .corner_radius = .all(6),
                        .background_color = if(cl.hovered()) LightGray else White,
                    })({
                        cl.text(paletteName, .{
                            .alignement = .center,
                            .color = Black,
                            .font_size = FontSize,
                            .font_id = 0,
                        });
                    });


                    for(GBCPalettes[i]) |color|{
                        cl.UI()(.{
                            .layout = .{
                                .sizing = .{.h = .fixed(30) ,.w = .fixed(30)},
                            },
                            .background_color = color,
                        })({

                        });
                    }
                }); 
            }
        });
    }

    fn GBCscreen(self : *GUI)void{

        cl.UI()(.{
            .id = .ID("GBC"),
            .layout = .{
                .sizing = .grow,
                .child_alignment = .{.x = .center, .y = .center}, 
            },
        })({

            cl.UI()(.{
                .id = .ID("Screen"),
                .layout = .{
                    .sizing = .grow,
                },
                .aspect_ratio = .{.aspect_ratio = 160.0/144.0},
                .image = .{.image_data = &self.CGBtexture},
            })({
    
            });
        });
    }

    fn FilePicker(self : *GUI) void{

        cl.UI()(.{
            .id = .ID("SideBar"),
            .layout = .{
                .sizing = .{.w = cl.SizingAxis.percent(0.33), .h = .grow},
                .direction = .top_to_bottom, 
                .child_gap = 4             
            },
        })({

            cl.UI()(.{
                .id = .ID("Directory Header"),
                .layout = .{
                    .sizing = .{.h = .fit,.w = .grow},
                    .direction = .left_to_right,
                    .child_alignment = .{.x = .left ,.y = .center},
                    .child_gap = 2,
                },
            })({

                cl.UI()(.{
                    .layout = .{
                        .sizing = .{.h = .fit,.w = .grow},
                        .child_alignment = .{.x = .left,.y = .center},
                        .padding = .{.left = 12, .right = 12, .top = 12,.bottom = 12},
                    },
                    .clip = .{.horizontal = true, .child_offset = cl.getScrollOffset()},
                    .corner_radius = .all(10),
                    .background_color = White,
                    .border = .{
                        .width = .{.left = 5, .right = 5,.top = 5,.bottom = 5},
                        .color = DarkGray,
                    }
                })({
                    cl.text(self.cwd, .{
                        .alignement = .left,
                        .color = Black,
                        .font_size = FontSize,
                        .wrap_mode = .words
                    });
                });
                

                cl.UI()(.{
                    .layout = .{
                        .sizing = .{.h = .fit,.w = .fit},
                        .child_alignment = .{.x = .center,.y = .center},
                        .padding = .{.left = 12, .right = 12, .top = 12,.bottom = 12},
                    },
                    .corner_radius = .all(10),
                    .background_color = White,
                    .border = .{
                        .width = .{.left = 5, .right = 5,.top = 5,.bottom = 5},
                        .color = DarkGray,
                    }
                })({
                    BasicButton("<-");
                });
            });

            cl.UI()(.{
                .id = .ID("File Browser"),
                .layout = .{
                    .sizing = .{.w = .grow, .h = .grow},
                    .direction = .top_to_bottom,
                    .child_gap = 8,
                    .child_alignment = .{.x = .left, .y = .top},
                    .padding = .{.left = 12, .right = 8, .top = 8,.bottom = 8},
                },

                // We need to clip this so that we can scroll through files
                .clip = .{.vertical = true, .child_offset = cl.getScrollOffset()},
                .corner_radius = .all(10),
                .background_color = White,
                .border = .{
                    .width = .{.left = 5, .right = 5,.top = 5,.bottom = 5},
                    .color = DarkGray,
                }
            })({
                
                // List of Files
                for(self.RomList.items) |file| {
                    cl.UI()(.{
                        .id = .ID(file.name),
                        .layout = .{
                            .sizing = .{.h = .fit,.w = .grow},
                            .child_alignment = .{.x = .left,.y = .center},
                            .padding = .{.left = 0, .right = 8, .top = 2,.bottom = 2},
                        },
                        .corner_radius = .all(6),
                        .background_color = if(cl.hovered()) LightGray else White,
                    })({
                        cl.text(file.name, .{
                            .font_id = 0,
                            .color = Black,
                            .font_size = FontSize,
                            .alignement = .left
                        });

                    });
                }
            });

            cl.UI()(.{
                .id = .ID("Rom Select"),
                .layout = .{
                    .sizing = .{.h = .fit,.w = .grow},
                    .direction = .left_to_right,
                    .child_alignment = .{.x = .left ,.y = .center},
                    .child_gap = 8,
                    .padding = .{.left = 12, .right = 12, .top = 12,.bottom = 12},
                },
                .corner_radius = .all(10),
                .background_color = White,
                .border = .{
                    .width = .{.left = 5, .right = 5,.top = 5,.bottom = 5},
                    .color = DarkGray,
                }
            })({
                cl.text(self.SelectedRom, .{
                    .alignement = .center,
                    .color = Black,
                    .font_size = FontSize,
                });

                cl.UI()(.{.layout = .{.sizing = .{.w = .grow}}})({});

                BasicButton("Cancel");
                BasicButton("Open");
            });
        });

    }

    fn ChangeDirectory(self : *GUI, subPath : []const u8) void {

        self.cwd = blk: {
            if(std.mem.eql(u8, subPath, "..")) {
                // go to parent directory
                const ParentDir = self.gpa.allocator().dupe(u8,std.fs.path.dirname(self.cwd) orelse self.cwd)
                catch break :blk self.cwd;

                if(self.PathAllocated) self.gpa.allocator().free(self.cwd);
                self.PathAllocated = true;
                break :blk ParentDir;

            }else{
                // go into child directory

                // Create the Child Path
                const ChildAddress = std.fs.path.join(self.gpa.allocator(), &[_][]const u8{self.cwd,subPath})
                catch break :blk self.cwd;
                defer self.gpa.allocator().free(ChildAddress); // free local path

                // Make a copy to place into our cwd
                const ChildAddressCopy = self.gpa.allocator().dupe(u8, ChildAddress)
                catch break :blk self.cwd;
                
                // if path was previously allocated free it
                if(self.PathAllocated) self.gpa.allocator().free(self.cwd);
                self.PathAllocated = true; // note down that we are allocating

                // lastly return the copy and free the local var 
                break :blk ChildAddressCopy;
                
            }
        };
    }

    fn clearFileList(self : *GUI) void{
        self.SelectedRom = "Please Select A Rom";
        for(self.RomList.items) |file|{
            self.gpa.allocator().free(file.name);
        }
        // leave the ".." directory still there
        self.RomList.clearAndFree();
    }

    fn scanDir(self : *GUI) !void{

        self.clearFileList();

        // TODO : Make it So that it will fail and bring a pop up
        var Dir = try std.fs.openDirAbsolute(self.cwd, .{ .iterate = true });
        defer Dir.close();

        var iter = Dir.iterate();

        // we will append the files names to our array list
        while(try iter.next()) |entry|{
            // continue if its not a gb gbc or directory
            if(!std.mem.eql(u8, std.fs.path.extension(entry.name), ".gbc") and !std.mem.eql(u8, std.fs.path.extension(entry.name), ".gb") and !(entry.kind == .directory)) continue;
            
            const fileName = try self.gpa.allocator().dupe(u8, entry.name);
            try self.RomList.append(std.fs.Dir.Entry{.kind = entry.kind,.name = fileName});
        }
    }

    // Tab Bar Functions
    fn TabBar(self : *GUI)void {

        cl.UI()(.{
            .id = .ID("TabBar"),
            .layout = .{
                .sizing = .{.h = .fixed(50), .w = .grow},
                .child_gap = 12,
                .child_alignment = .{.x = .left, .y = .center},
                .padding = .all(10),
            },
            .corner_radius = .all(10),
            .background_color = White,
            .border = .{
                .width = .{.left = 5, .right = 5,.top = 5,.bottom = 5},
                .color = DarkGray,
            }
        })({
            // Tab Elements
            cl.UI()(.{
                .id = .ID("File Button"),
                .layout = .{
                    .sizing = .{.h = .fixed(30), .w = .fit},
                    .child_alignment = .{.x = .center,.y = .center},
                    .padding = .{.left = 16, .right = 16,.top = 4,.bottom = 4},
                },
                .background_color = if(cl.hovered() or self.showFileDropdown) LightGray else White,
                .corner_radius = if(self.showFileDropdown) .{.top_left = 4, .top_right = 4} else .all(6),
            })({
                cl.text("File", .{
                    .font_id = 0,
                    .color = Black,
                    .font_size = FontSize,
                    .letter_spacing = 1,
                });

                if(self.showFileDropdown){
                    cl.UI()(.{
                        .id = .ID("File Menu"),
                        .layout = .{
                            .direction = .top_to_bottom,
                            .sizing = .{.w = .fit, .h = .fit},
                            .child_alignment = .{.x = .left},
                            .padding = .{.top = 4,.bottom = 4}
                        },
                        .floating = .{
                            .attach_points = .{.element = .left_top , .parent = .left_bottom},
                            .attach_to = .to_parent,
                        },
                        .corner_radius = .{.bottom_left = 10, .bottom_right = 10 , .top_right = 10},
                        .background_color = LightGray,
                    })({
                        DropDownButton("Select Rom");
                        DropDownButton("Reset");
                        DropDownButton("Exit");
                    });
                }
            });
            cl.UI()(.{
                .id = .ID("View Button"),
                .layout = .{
                    .sizing = .{.h = .fixed(30), .w = .fit},
                    .child_alignment = .{.x = .center,.y = .center},
                    .padding = .{.left = 16, .right = 16,.top = 4,.bottom = 4},
                },
                .background_color = if(cl.hovered() or self.showViewDropdown) LightGray else White,
                .corner_radius = if(self.showViewDropdown) .{.top_left = 4, .top_right = 4} else .all(6),
            })({
                cl.text("View", .{
                    .font_id = 0,
                    .color = Black,
                    .font_size = FontSize,
                    .letter_spacing = 1,
                });

                if(self.showViewDropdown){
                    cl.UI()(.{
                        .id = .ID("View Menu"),
                        .layout = .{
                            .direction = .top_to_bottom,
                            .sizing = .{.w = .fit, .h = .fit},
                            .child_alignment = .{.x = .left},
                            .padding = .{.top = 4,.bottom = 4}
                        },
                        .floating = .{
                            .attach_points = .{.element = .left_top , .parent = .left_bottom},
                            .attach_to = .to_parent,
                        },
                        .corner_radius = .{.bottom_left = 10, .bottom_right = 10 , .top_right = 10},
                        .background_color = LightGray,
                    })({
                        DropDownButton("Settings");
                        DropDownButton("Debug");
                    });
                }
            });
        });
    }

    fn DropDownButton(name : []const u8) void{
        cl.UI()(.{
            .id = .ID(name),
            .layout = .{
                .sizing = .{.h = .fixed(30), .w = .grow},
                .child_alignment = .{.x = .left,.y = .center},
                .padding = .{.left = 8, .right = 16,.top = 4,.bottom = 4},
            },
            .background_color = if(cl.hovered()) White else LightGray,
        })({
            cl.text(name, .{
                .font_id = 0,
                .color = GBCPalettes[0][0],
                .font_size = FontSize,
                .letter_spacing = 1,
            });
        }); 
    }

    fn BasicButton(name : []const u8) void {
        cl.UI()(.{
            .id = .ID(name),
            .layout = .{
                .sizing = .{.h = .fixed(30), .w = .fit},
                .child_alignment = .{.x = .center,.y = .center},
                .padding = .{.left = 16, .right = 16,.top = 4,.bottom = 4},
            },
            .background_color = if(cl.hovered()) White else LightGray,
            .corner_radius = .all(6),
            .border = .{
                .width = .all(2),
                .color = DarkGray,
            }
        })({
            cl.text(name, .{
                .font_id = 0,
                .color = Black,
                .font_size = FontSize,
                .letter_spacing = 1,
            });
        });
    }

    fn UpdateWindowSize() void{
        cl.setLayoutDimensions(.{ .h = @floatFromInt(rl.getScreenHeight()) ,.w = @floatFromInt(rl.getScreenWidth()) });
    }

    fn UpdateMouse(self : *GUI) void{
        const mouse :rl.Vector2  = rl.getMousePosition();
        const scroll :rl.Vector2 = rl.getMouseWheelMoveV();
        self.MouseClicked = rl.isMouseButtonPressed(.left);
        cl.setPointerState(cl.Vector2{.x = mouse.x,.y = mouse.y}, self.MouseClicked);
        cl.updateScrollContainers(true, cl.Vector2{.x = scroll.x,.y = scroll.y*2},rl.getFrameTime());
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

        // Check File Selection
        for(self.RomList.items) |file|{
            if(self.checkClickedItem(file.name)){

                switch (file.kind) {
                    .file => self.SelectedRom = file.name,
                    .directory => {
                        self.ChangeDirectory(file.name);
                        self.scanDir() catch std.debug.print("Scan Failed", .{});
                        break;
                    },
                    else => break,
                }
            }
        }

        // of the open button is pressed load the rom 
        if(self.checkClickedItem("Open")){

            if(std.mem.eql(u8, self.SelectedRom, "Please Select A Rom")) return
            if(!std.mem.eql(u8, self.LoadedRom, "None")) self.gpa.allocator().free(self.LoadedRom);
            self.LoadedRom = std.fs.path.join(self.gpa.allocator(), &[_][]const u8{self.cwd,self.SelectedRom}) catch return;
            
            self.loadRom();
            self.showFileBrowser = false;
        }
        if(self.checkClickedItem("Cancel")){
            self.showFileBrowser = false;
        }

        if(self.checkClickedItem("<-")){
            self.ChangeDirectory("..");
            self.scanDir() catch std.debug.print("Scan Failed", .{});
        }

        // File Button And Dropdown Menu
        if(self.checkClickedItem("File Button")){
            self.showFileDropdown = true;
        }else if(self.MouseClicked) self.showFileDropdown = false;

        if(self.checkClickedItem("Select Rom")){
            self.showFileBrowser = !self.showFileBrowser;
        }

        if(self.checkClickedItem("Reset")){
            if(self.gbc) |_| {
                self.loadRom();
            }
        }

        if(self.checkClickedItem("Exit")){
            self.Exit = true;
        }

        // View Button and Drop down Menu
        if(self.checkClickedItem("View Button")){
            self.showViewDropdown = true;
        }else if(self.MouseClicked) self.showViewDropdown = false;

        if(self.checkClickedItem("Settings")){
            self.showSettings = !self.showSettings;
        }

        for(PaletteNames,0..) |paletteName,i|{
            if(self.checkClickedItem(paletteName)) {
                UpdatePalette(i);
                if(self.gbc) |gbc| gbc.ppu.pmem.SelectUserPalette(i);
            }
        }
            
    }
    fn checkClickedItem(self : * GUI, StringID : []const u8) bool {
        return cl.pointerOver(cl.getElementId(StringID)) and self.MouseClicked;
    }

    fn loadRom(self :*GUI) void{
        
        self.ExitEmulator();
        
        self.gbc = self.pageAlloc.create(GBC) catch return;
        self.gbc.?.init(self,self.LoadedRom) catch self.ExitEmulator();
        self.gbc.?.ppu.pmem.SelectUserPalette(GBPaletteIndex);
    }

    pub fn ExitEmulator(self : *GUI)void{

        if(self.gbc) |gbc|{
            gbc.deinit();
            self.pageAlloc.destroy(gbc);
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

    fn deinit(self : *GUI) void {
        // Close Emulator
        self.ExitEmulator();

        // Free Possible Allocated Rom Path
        if(!std.mem.eql(u8, self.LoadedRom, "None")) self.gpa.allocator().free(self.LoadedRom);
        // Free Possible Allocated Path
        if(self.PathAllocated)self.gpa.allocator().free(self.cwd);

        // Deinit Our RomList
        for(self.RomList.items) |file|{
            self.gpa.allocator().free(file.name);
        }
        self.RomList.deinit();

        // free clay memory
        self.pageAlloc.free(self.ClayMem);
        _ = self.gpa.deinit();

        //close and unload raylib textures
        rl.unloadTexture(self.CGBtexture);
        rl.closeWindow();
    }
};

fn Header(text : []const u8)void{

    cl.UI()(.{
        .layout = .{
            .sizing = .{.w = .grow,.h = .fit},
            .direction = .left_to_right,
            .child_alignment = .center,    
        }
    })({
        PadWidth();
        cl.text(text, .{
            .alignement = .center,
            .color = Black,
            .font_size = HeaderFontSize,
            .font_id = 0,
        });
        PadWidth();
    }); 
}

fn PadWidth()void{
    cl.UI()(.{.layout = .{.sizing = .{.w = .grow}}})({});
}

fn PadHeight()void{
    cl.UI()(.{.layout = .{.sizing = .{.h = .grow}}})({});
}

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