const term = @import("thermit");
const std = @import("std");

pub const Term = struct {
    tty: term.Terminal,

    // frameBuffer: []u8,
    frameBuffer: std.ArrayListUnmanaged(u8),
    size: term.Size,

    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) !Term {
        const fd = try std.posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0);
        const file = std.fs.File{ .handle = fd };

        try term.enterAlternateScreen(file.writer());
        var tty = try term.Terminal.init(file);

        try tty.enableRawMode();
        try term.cursorHide(file.writer());

        const size = try term.getWindowSize(fd);

        // const x, const y = size;
        // const frameBuffer = try a.alloc(u8, x * y);
        // @memset(frameBuffer, 0);

        return .{
            .tty = tty,
            // .frameBuffer = frameBuffer,
            .frameBuffer = try std.ArrayListUnmanaged(u8).initCapacity(a, size[0] * size[1]),
            .size = size,
            .a = a,
        };
    }

    pub const Screen = packed struct(u64) { x: u16, y: u16, w: u16, h: u16 };

    /// Creates a screen at the given position, if width or height is null then
    /// it extends to the end of the screen
    pub fn makeScreen(self: Term, x: u16, y: u16, w: ?u16, h: ?u16) Screen {
        return .{
            .x = x,
            .y = y,
            .w = w orelse self.size[0] - x,
            .h = h orelse self.size[1] - y,
        };
    }

    pub fn draw(self: *Term, screen: Screen, row: u16, col: u16, data: []const u8) !void {
        std.debug.assert(screen.x <= self.size[0]);
        std.debug.assert(screen.y <= self.size[1]);
        std.debug.assert(row <= screen.h);
        std.debug.assert(col <= screen.w);

        var wr = self.frameBuffer.writer(self.a);

        try term.moveCol(wr, screen.x + col);
        try term.moveRow(wr, screen.y + row);
        const len = self.size[0] - (screen.x + col);
        const line = if (data.len > len) data[0..len] else data;
        try wr.writeAll(line);
    }

    pub fn start(self: *Term, resize: bool) !void {
        if (resize) {
            self.size = try term.getWindowSize(self.tty.f.handle);
        }
        self.frameBuffer.shrinkRetainingCapacity(0);
    }

    /// Flushes out the current buffer to the screen
    pub fn finish(self: Term) !void {
        // const x, const y = self.size;

        // var buf = std.ArrayList(u8).init(self.a);
        // defer buf.deinit();
        // const wr = buf.writer();
        //
        // try term.moveTo(wr, 0, 0);
        // // try term.clear(wr, .All);
        //
        // for (0..y) |r| {
        //     const data = self.frameBuffer[r * x .. (r + 1) * x];
        //     const trim = std.mem.trim(u8, data, &.{0});
        //     const st: u16 = @intCast(@intFromPtr(trim.ptr - @as(usize, @intFromPtr(data.ptr))));
        //
        //     try term.moveCol(wr, st);
        //     try wr.writeAll(trim);
        //     try term.nextLine(wr, 1);
        // }
        //
        // try self.tty.f.writeAll(buf.items);
        try self.tty.f.writeAll(self.frameBuffer.items);

        try std.posix.syncfs(self.tty.f.handle);
    }

    pub fn deinit(self: *Term) void {
        term.cursorShow(self.tty.f.writer()) catch {};

        self.tty.disableRawMode() catch {};
        term.leaveAlternateScreen(self.tty.f.writer()) catch {};

        self.tty.f.close();

        self.tty.deinit();
        self.frameBuffer.deinit(self.a);
        // self.a.free(self.frameBuffer);
    }
};
