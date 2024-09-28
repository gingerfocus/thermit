const term = @import("thermit");
const std = @import("std");

pub const Term = struct {
    tty: term.Terminal,

    frameBuffer: []u8,
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

        const x, const y = size;
        const frameBuffer = try a.alloc(u8, x * y);
        @memset(frameBuffer, 0);

        return .{
            .tty = tty,
            .frameBuffer = frameBuffer,
            .size = size,
            .a = a,
        };
    }

    pub const Screen = packed struct(u64) {
        x: u16,
        y: u16,
        w: u16,
        h: u16,
    };

    pub fn draw(self: Term, screen: Screen, row: u16, pad: u16, arg_data: []const u8) void {
        var data = arg_data;
        std.debug.assert(screen.x <= self.size[0]);
        std.debug.assert(screen.y <= self.size[1]);
        std.debug.assert(row <= screen.h);
        std.debug.assert(pad <= screen.w);

        const offset = (screen.y + row) * self.size[0] + screen.x;
        var line = self.frameBuffer[offset .. offset + screen.w];

        // std.debug.assert(data.len <= screen.w - pad);
        @memset(line[0..pad], 0);
        line = line[pad..];

        if (data.len <= line.len) {
            line = line[0..data.len];
        } else {
            data = data[0..line.len];
        }
        @memcpy(line, data);
    }

    pub fn start(self: *Term, resize: bool) !void {
        if (resize) {
            self.size = try term.getWindowSize(self.tty.f.handle);
            self.frameBuffer = try self.a.realloc(self.frameBuffer, self.size[0] * self.size[1]);
        }
        @memset(self.frameBuffer, 0);
    }

    /// Flushes out the current buffer to the screen
    pub fn finish(self: Term) !void {
        const x, const y = self.size;

        var buf = std.ArrayList(u8).init(self.a);
        defer buf.deinit();
        const wr = buf.writer();

        try term.moveTo(wr, 0, 0);
        // try term.clear(wr, .All);

        for (0..y) |r| {
            const data = self.frameBuffer[r * x .. (r + 1) * x];
            const trim = std.mem.trim(u8, data, &.{0});
            const st: u16 = @intCast(@intFromPtr(trim.ptr - @as(usize, @intFromPtr(data.ptr))));

            try term.moveCol(wr, st);
            try wr.writeAll(trim);
            try term.nextLine(wr, 1);
        }

        try self.tty.f.writeAll(buf.items);

        try std.posix.syncfs(self.tty.f.handle);
    }

    pub fn deinit(self: *Term) void {
        term.cursorShow(self.tty.f.writer()) catch {};

        self.tty.disableRawMode() catch {};
        term.leaveAlternateScreen(self.tty.f.writer()) catch {};

        self.tty.deinit();
        self.a.free(self.frameBuffer);
    }
};
