const std = @import("std");
const c = @import("c.zig");
const sdl = @import("sdl.zig");

const vertexSource: [*]const u8 =
    c\\ attribute vec4 position;
    c\\ void main()
    c\\ {
    c\\     gl_Position = vec4(position.xyz, 1.0);
    c\\ }
;
const fragmentSource: [*]const c.GLchar =
    c\\ precision mediump float;
    c\\ void main()
    c\\ {
    c\\     gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
    c\\ }
;

const TransitionTag = enum {
    PushScreen,
    PopScreen,
    None,
};

const Transition = union(TransitionTag) {
    PushScreen: *Screen,
    PopScreen: void,
    None: void,
};

const Screen = struct {
    startFn: ?fn (self: *Screen) void = null,
    updateFn: fn (self: *Screen, keys: [*]const u8) Transition,
    renderFn: fn (self: *Screen, *c.SDL_Renderer) anyerror!void,
    stopFn: ?fn (self: *Screen) void = null,
    deinitFn: ?fn (self: *Screen) void = null,

    pub fn start(self: *Screen) void {
        if (self.startFn) |func| {
            return func(self);
        }
    }

    pub fn update(self: *Screen, keys: [*]const u8) Transition {
        return self.updateFn(self, keys);
    }

    pub fn render(self: *Screen, ren: *c.SDL_Renderer) !void {
        return self.renderFn(self, ren);
    }

    pub fn stop(self: *Screen) void {
        if (self.stopFn) |func| {
            return func(self);
        }
    }

    pub fn deinit(self: *Screen) void {
        if (self.deinitFn) |func| {
            func(self);
        }
    }
};

pub fn main() !void {
    const allocator = std.heap.direct_allocator;

    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        return sdl.logErr(error.InitFailed);
    }
    defer c.SDL_Quit();

    const win = c.SDL_CreateWindow(c"Hello World!", 100, 100, 640, 480, c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_OPENGL) orelse {
        return sdl.logErr(error.CouldntCreateWindow);
    };
    defer c.SDL_DestroyWindow(win);

    const ren = c.SDL_CreateRenderer(win, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC) orelse {
        return sdl.logErr(error.CouldntCreateRenderer);
    };
    defer c.SDL_DestroyRenderer(ren);

    if ((c.IMG_Init(c.IMG_INIT_PNG) & c.IMG_INIT_PNG) != c.IMG_INIT_PNG) {
        return sdl.logErr(error.ImgInit);
    }

    const kw_driver = c.KW_CreateSDL2RenderDriver(ren, win);
    defer c.KW_ReleaseRenderDriver(kw_driver);

    const set = c.KW_LoadSurface(kw_driver, c"lib/kiwi/examples/tileset/tileset.png");
    defer c.KW_ReleaseSurface(kw_driver, set);

    const gui = c.KW_Init(kw_driver, set) orelse {
        return error.CouldntInitGUI;
    };
    defer c.KW_Quit(gui);

    var geometry = c.KW_Rect{ .x = 0, .y = 0, .w = 320, .h = 240 };
    var frame = c.KW_CreateFrame(gui, null, &geometry);

    var labelrect_ = c.KW_Rect{ .x = 0, .y = 0, .w = 320, .h = 100 };
    const labelrect: [*c]c.KW_Rect = &labelrect_;
    var playbuttonrect_: c.KW_Rect = c.KW_Rect{ .x = 0, .y = 0, .w = 320, .h = 100 };
    const playbuttonrect: [*c]c.KW_Rect = &playbuttonrect_;

    var rects_array = [_][*c]c.KW_Rect{ labelrect, playbuttonrect };
    const rects = rects_array[0..2].ptr;

    var weights_array = [_]c_uint{ 2, 1 };
    const weights = weights_array[0..2].ptr;

    c.KW_RectFillParentVertically(&geometry, rects, weights, 2, 10);
    const label = c.KW_CreateLabel(gui, frame, c"Label with an icon :)", labelrect);
    const playbutton = c.KW_CreateButtonAndLabel(gui, frame, c"Play", playbuttonrect) orelse unreachable;

    const iconrect = c.KW_Rect{ .x = 0, .y = 48, .w = 24, .h = 24 };
    c.KW_SetLabelIcon(label, &iconrect);

    var quit = false;
    var screenStarted = false;
    var e: c.SDL_Event = undefined;
    const keys = c.SDL_GetKeyboardState(null);

    var screens = std.ArrayList(*Screen).init(allocator);
    try screens.append(&(try MenuScreen.init(allocator, gui, playbutton)).screen);

    while (!quit) {
        const currentScreen = screens.toSlice()[screens.len - 1];
        if (!screenStarted) {
            currentScreen.start();
            screenStarted = true;
        }

        while (c.SDL_PollEvent(&e) != 0) {
            if (e.type == c.SDL_QUIT) {
                quit = true;
            }
        }

        const transition = currentScreen.update(keys);

        _ = c.SDL_RenderClear(ren);
        try currentScreen.render(ren);
        c.SDL_RenderPresent(ren);

        switch (transition) {
            .PushScreen => |newScreen| {
                currentScreen.stop();
                try screens.append(newScreen);
                screenStarted = false;
            },
            .PopScreen => {
                currentScreen.stop();
                screens.pop().deinit();
                if (screens.len == 0) {
                    quit = true;
                }
                screenStarted = false;
            },
            .None => {},
        }
    }
}

const MenuScreen = struct {
    allocator: *std.mem.Allocator,
    screen: Screen,
    gui: *c.KW_GUI,
    playButtonPressed: *bool,

    fn init(allocator: *std.mem.Allocator, gui: *c.KW_GUI, button: *c.KW_Widget) !*MenuScreen {
        const self = try allocator.create(MenuScreen);
        self.allocator = allocator;
        self.screen = Screen{
            .startFn = start,
            .updateFn = update,
            .renderFn = render,
            .deinitFn = deinit,
        };
        self.gui = gui;
        self.playButtonPressed = try allocator.create(bool);
        self.playButtonPressed.* = false;

        c.KW_SetWidgetUserData(button, @ptrCast(*c_void, self.playButtonPressed));
        c.KW_AddWidgetMouseDownHandler(button, onPlayPressed);

        return self;
    }

    fn start(screen: *Screen) void {
        const self = @fieldParentPtr(MenuScreen, "screen", screen);
        self.playButtonPressed.* = false;
    }

    fn update(screen: *Screen, keys: [*]const u8) Transition {
        const self = @fieldParentPtr(MenuScreen, "screen", screen);

        c.KW_ProcessEvents(self.gui);

        if (self.playButtonPressed.*) {
            const play_screen = PlayScreen.init(self.allocator) catch unreachable;
            return Transition{ .PushScreen = &play_screen.screen };
        }

        if (keys[sdl.scnFromKey(c.SDLK_ESCAPE)] == 1) {
            return Transition{ .PopScreen = {} };
        }
        return Transition{ .None = {} };
    }

    fn render(screen: *Screen, ren: *c.SDL_Renderer) anyerror!void {
        const self = @fieldParentPtr(MenuScreen, "screen", screen);

        c.KW_Paint(self.gui);
    }

    fn deinit(screen: *Screen) void {
        const self = @fieldParentPtr(MenuScreen, "screen", screen);
        self.allocator.destroy(self.playButtonPressed);
        self.allocator.destroy(self);
    }

    extern fn onPlayPressed(widget: ?*c.KW_Widget, mouse_button: c_int) void {
        const playButtonPressed = @ptrCast(*bool, c.KW_GetWidgetUserData(widget));
        playButtonPressed.* = true;
    }
};

const PlayScreen = struct {
    allocator: *std.mem.Allocator,
    screen: Screen,

    fn init(allocator: *std.mem.Allocator) !*PlayScreen {
        const self = try allocator.create(PlayScreen);
        self.allocator = allocator;
        self.screen = Screen{
            .updateFn = update,
            .renderFn = render,
            .deinitFn = deinit,
        };
        return self;
    }

    fn update(screen: *Screen, keys: [*]const u8) Transition {
        const self = @fieldParentPtr(MenuScreen, "screen", screen);
        if (keys[sdl.scnFromKey(c.SDLK_ESCAPE)] == 1) {
            return Transition{ .PopScreen = {} };
        }
        return Transition{ .None = {} };
    }

    fn render(screen: *Screen, ren: *c.SDL_Renderer) anyerror!void {
        const self = @fieldParentPtr(MenuScreen, "screen", screen);
    }

    fn deinit(screen: *Screen) void {
        const self = @fieldParentPtr(MenuScreen, "screen", screen);
        self.allocator.destroy(self);
    }
};
