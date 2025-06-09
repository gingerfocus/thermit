pub const thermit = @import("thermit");

const std = @import("std");
const trm = thermit;

const Color = trm.Color;

pub const Cell = struct {
    symbol: u21 = 0,
    fg: Color = .Reset,
    bg: Color = .Reset,
    /// Zeroed value is to not render the cell, this allows the array to just
    /// be memset to zero to reset frame buffer
    render: bool = false,

    pub inline fn _setSymbol(self: *Cell, char: u21) void {
        self.symbol = char;
    }
};

pub const Term = struct {
    tty: trm.Terminal,
    buffer: []Cell,
    size: trm.Size,

    cursor: ?trm.Size = null,

    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) !Term {
        const fd = try std.posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0);
        const file = std.fs.File{ .handle = fd };

        try trm.enterAlternateScreen(file.writer());
        var tty = try trm.Terminal.init(file);

        try tty.enableRawMode();

        const size = try trm.getWindowSize(fd);

        const buffer = try a.alloc(Cell, size.x * size.y);

        return .{
            .tty = tty,
            .buffer = buffer,
            .size = size,
            .a = a,
        };
    }

    pub fn deinit(self: *Term) void {
        const wr = self.tty.f.writer();
        trm.cursorShow(wr) catch {};

        self.tty.disableRawMode() catch {};
        trm.leaveAlternateScreen(wr) catch {};

        self.tty.f.close();
        self.tty.deinit();

        self.a.free(self.buffer);
    }

    pub const Screen = packed struct(u64) { x: u16, y: u16, w: u16, h: u16 };

    /// Creates a screen at the given position, if width or height is null then
    /// it extends to the end of the screen
    pub fn makeScreen(self: Term, x: u16, y: u16, w: ?u16, h: ?u16) Screen {
        return .{
            .x = x,
            .y = y,
            .w = w orelse self.size.x - x,
            .h = h orelse self.size.y - y,
        };
    }

    pub fn getCell(self: Term, x: u16, y: u16) ?*Cell {
        const i = (y * self.size.x) + x;
        if (i >= self.buffer.len) return null;

        const ptr = &self.buffer[i];
        ptr.render = true;
        return ptr;
    }

    pub fn getScreenCell(self: Term, screen: Screen, x: u16, y: u16) ?*Cell {
        std.debug.assert(screen.x <= self.size.x);
        std.debug.assert(screen.y <= self.size.y);
        std.debug.assert(x <= screen.w);
        std.debug.assert(y <= screen.h);

        return self.getCell(screen.x + x, screen.y + y);
    }

    // pub const draw = @compileError(
    //     \\Function `draw` is depricated, consider using `getScreenCell` in a
    //     \\loop or `writeBuffer` if that is what you really need
    // );

    pub fn writeBuffer(self: Term, screen: Screen, x: u16, y: u16, buffer: []const u8) void {
        var col: u16 = x;
        for (buffer) |ch| {
            if (!(col < screen.w)) return;

            const cell = self.getScreenCell(screen, col, y) orelse return;
            cell.symbol = ch;

            col += 1;
        }
    }

    pub fn moveCursor(self: *Term, screen: Screen, x: u16, y: u16) void {
        self.cursor = .{ .x = screen.x + x, .y = screen.y + y };
    }

    pub fn start(self: *Term, resize: bool) !void {
        if (resize) {
            self.size = try trm.getWindowSize(self.tty.f.handle);
            self.buffer = try self.a.realloc(self.buffer, self.size.x * self.size.y);
        }
        @memset(self.buffer, Cell{});
    }

    /// Flushes out the current buffer to the screen
    pub fn finish(self: Term) !void {
        var buf = std.ArrayList(u8).init(self.a);
        defer buf.deinit();
        const wr = buf.writer();

        try trm.cursorHide(wr);
        // try trm.clear(wr, .All);

        var fg = Color.Reset;
        var bg = Color.Reset;
        // var modifier = Modifier{};

        // -1 so that when adding later it doesnt overflow
        var pos: trm.Size = .{ .x = std.math.maxInt(u16) - 1, .y = std.math.maxInt(u16) - 1 };

        var i: u16 = 0;
        for (self.buffer) |cell| {
            defer i += 1;
            if (!cell.render) continue;

            const x: u16 = i % self.size.x;
            const y: u16 = i / self.size.x;

            if (pos.x + 1 != x or pos.y != y) {
                try trm.moveTo(wr, x, y);
            }
            pos = .{ .x = x, .y = y };

            // TODO: check modifier is same and change update if not

            if (cell.fg != fg) {
                try cell.fg.writeSequence(wr.any(), .Foreground);
                fg = cell.fg;
            }

            if (cell.bg != bg) {
                try cell.bg.writeSequence(wr.any(), .Background);
                bg = cell.bg;
            }

            var codepoint: [4]u8 = undefined;
            const s = try std.unicode.utf8Encode(cell.symbol, &codepoint);
            try wr.writeAll(codepoint[0..s]);
        }
        // TODO: reset all color and attris at end

        if (self.cursor) |loc| {
            try trm.moveTo(wr, loc.x, loc.y);
            try trm.cursorShow(wr);
        } // else keep cursor hidden

        // write buffer to terminal
        try self.tty.f.writeAll(buf.items);

        // let the terminal deal with all the shit we just wrote
        try std.posix.syncfs(self.tty.f.handle);
    }
};

/// Logging utility class for setting file logging in terminal programs
pub const log = struct {
    pub var file: ?std.fs.File = null;

    /// File ownership is still maintained by the caller and *you* must close
    // it. If you need access to it at a later point use `getFile`. Argument
    // can be null which removes the log file.
    //
    // DEPRICATED: just set the file variable
    pub fn _setFile(f: ?std.fs.File) void {
        file = f;
    }

    /// Gets the file used for logging if any
    ///
    // DEPRICATED: just reference the file variable
    pub fn _getFile() ?std.fs.File {
        return file;
    }

    fn levelToText(level: std.log.Level) []const u8 {
        return switch (level) {
            .err => "ERROR",
            .warn => "WARN",
            .info => "INFO",
            .debug => "DEBUG",
            // else => "UNKNOWN",
        };
    }

    pub fn toFile(
        comptime level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = scope;
        if (file) |f| {
            const lvl = comptime levelToText(level);
            const fmt = lvl ++ ": " ++ format ++ "\n";
            std.fmt.format(f.writer(), fmt, args) catch {};
        }
    }

    pub fn toNull(
        comptime _: std.log.Level,
        comptime _: @TypeOf(.enum_literal),
        comptime _: []const u8,
        _: anytype,
    ) void {}
};
