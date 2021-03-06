const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");
const sdl = @import("sdl.zig");
const screen = @import("screen.zig");
const Context = @import("context.zig").Context;
const assets = @import("assets.zig");
const kw_renderdriver = @import("kw_renderdriver_sdl_gpu.zig");
const audio = @import("audio.zig");
const leaderboard = @import("leaderboard.zig");
const LeaderBoard = leaderboard.LeaderBoard;
usingnamespace @import("constants.zig");

pub fn main() !void {
    const allocator = std.heap.direct_allocator;

    if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO) != 0) {
        return sdl.logErr(error.InitFailed);
    }
    defer c.SDL_Quit();

    const win = c.SDL_CreateWindow(c"Dodger", c.SDL_WINDOWPOS_UNDEFINED_MASK, c.SDL_WINDOWPOS_UNDEFINED_MASK, SCREEN_WIDTH, SCREEN_HEIGHT, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_OPENGL) orelse {
        return sdl.logErr(error.CouldntCreateWindow);
    };
    defer c.SDL_DestroyWindow(win);

    const winId = c.SDL_GetWindowID(win);

    c.GPU_SetPreInitFlags(c.GPU_INIT_DISABLE_VSYNC);
    c.GPU_SetInitWindow(winId);
    const gpuTarget = c.GPU_Init(SCREEN_WIDTH, SCREEN_HEIGHT, c.GPU_DEFAULT_INIT_FLAGS);
    defer c.GPU_Quit();

    if (c.TTF_Init() < 0) {
        return error.CouldntInitTTF;
    }
    defer c.TTF_Quit();

    var kw_driver = &kw_renderdriver.KW_GPU_RenderDriver.init(allocator, gpuTarget).driver;
    defer c.KW_ReleaseRenderDriver(kw_driver);

    var out_buffer = [_]u8{0} ** std.fs.MAX_PATH_BYTES;
    const exeDir = try std.fs.selfExeDirPath(&out_buffer);
    const rootDir = try std.fs.path.join(allocator, [_][]const u8{ exeDir, "assets" });

    // Hackishly adding null to end of path
    const tilesetPath = try std.fs.path.join(allocator, [_][]const u8{ rootDir, "tileset.png\x00" });

    const set = c.KW_LoadSurface(kw_driver, tilesetPath.ptr);
    defer c.KW_ReleaseSurface(kw_driver, set);

    const assetsStruct = &assets.Assets.init(allocator, rootDir);
    try assets.initAssets(assetsStruct);

    try audio.init(rootDir);

    var ctx = Context{
        .win = win,
        .kw_driver = kw_driver,
        .kw_tileset = set,
        .assets = assetsStruct,
        .leaderboard = &(try LeaderBoard.init(allocator)),
        .fps = 0,
    };
    defer ctx.leaderboard.deinit();

    var quit = false;
    var screenStarted = false;
    var e: c.SDL_Event = undefined;
    const keys = c.SDL_GetKeyboardState(null);

    var screens = std.ArrayList(*screen.Screen).init(allocator);
    try screens.append(&(try screen.menu.MenuScreen.init(allocator)).screen);

    var frame_timer = try std.time.Timer.start();

    while (!quit) {
        const currentScreen = screens.toSlice()[screens.len - 1];
        if (!screenStarted) {
            currentScreen.start(&ctx);
            screenStarted = true;
        }

        const transition = update: {
            while (c.SDL_PollEvent(&e) != 0) {
                switch (e.type) {
                    c.SDL_QUIT => quit = true,
                    c.SDL_KEYDOWN => {
                        const se = screen.ScreenEvent{
                            .sdl_event = &e,
                            .type = screen.ScreenEventData{ .KeyPressed = e.key.keysym.sym },
                        };
                        if (currentScreen.onEvent(se)) |t| {
                            break :update t;
                        }
                    },
                    else => {
                        const se = screen.ScreenEvent{
                            .sdl_event = &e,
                            .type = screen.ScreenEventData{ .Other = {} },
                        };
                        if (currentScreen.onEvent(se)) |t| {
                            break :update t;
                        }
                    },
                }
            }

            if (frame_timer.read() >= FRAME_TIME) {
                if (currentScreen.update(&ctx, keys)) |transition| {
                    break :update transition;
                }
                ctx.fps = (ctx.fps + @intToFloat(f32, std.time.ns_per_s) / @intToFloat(f32, frame_timer.read())) / 2;
                frame_timer.reset();
            }
            break :update null;
        };

        c.GPU_Clear(gpuTarget);
        try currentScreen.render(&ctx, gpuTarget);
        c.GPU_Flip(gpuTarget);

        if (transition) |t| {
            currentScreen.stop(&ctx);
            switch (t) {
                .PushScreen => |newScreen| try screens.append(newScreen),
                .ReplaceScreen => |newScreen| {
                    screens.pop().deinit();
                    try screens.append(newScreen);
                },
                .PopScreen => {
                    screens.pop().deinit();
                    if (screens.len == 0) {
                        quit = true;
                    }
                },
            }
            screenStarted = false;
        }
    }
}
