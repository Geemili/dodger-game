const std = @import("std");
const Allocator = std.mem.Allocator;
const StringHashMap = std.StringHashMap;
const c = @import("c.zig");
const sdl = @import("sdl.zig");
const EnemyBreed = @import("game/enemy.zig").EnemyBreed;
const constants = @import("constants.zig");
const Vec2 = @import("game/physics.zig").Vec2;

pub const Assets = struct {
    textures: StringHashMap(*c.GPU_Image),
    breeds: StringHashMap(EnemyBreed),

    pub fn init(allocator: *Allocator) Assets {
        return Assets{
            .textures = StringHashMap(*c.GPU_Image).init(allocator),
            .breeds = StringHashMap(EnemyBreed).init(allocator),
        };
    }

    pub fn loadTexture(self: *Assets, name: []const u8, filepath: [*]const u8) !void {
        const image = c.GPU_LoadImage(filepath);
        _ = try self.textures.put(name, image);
    }

    pub fn tex(self: *Assets, name: []const u8) *c.GPU_Image {
        return self.textures.get(name).?.value;
    }

    pub fn deinit(self: *Assets) void {
        var iter = self.textures.iterator();
        while (iter.next()) |texture| {
            c.SDL_DestroyTexture(texture.value);
        }
        self.textures.deinit();
        self.breeds.deinit();
    }
};

pub fn initAssets(assets: *Assets) !void {
    try assets.loadTexture("background", c"assets/background.png");
    try assets.loadTexture("guy", c"assets/guy.png");
    try assets.loadTexture("badguy", c"assets/badguy.png");

    _ = try assets.breeds.put("badguy", EnemyBreed{
        .texture = assets.tex("badguy"),
        .ticksOnFloor = constants.ENEMY_TICKS_ON_FLOOR,
        .collisionRectSize = Vec2{ .x = 27, .y = 28 },
    });
}
