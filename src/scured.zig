pub const thermit = @import("thermit");

const std = @import("std");
const trm = thermit;

// pub const FrameBuffers = std.AutoArrayHashMapUnmanaged(
//     Term.Screen,
//     std.ArrayListUnmanaged(u8),
// );

/// Adapted from ratatui
const Color = union(enum) {
    /// Resets the foreground or background color
    Reset,
    /// ANSI Color: Black. Foreground: 30, Background: 40
    Black,
    /// ANSI Color: Red. Foreground: 31, Background: 41
    Red,
    /// ANSI Color: Green. Foreground: 32, Background: 42
    Green,
    /// ANSI Color: Yellow. Foreground: 33, Background: 43
    Yellow,
    /// ANSI Color: Blue. Foreground: 34, Background: 44
    Blue,
    /// ANSI Color: Magenta. Foreground: 35, Background: 45
    Magenta,
    /// ANSI Color: Cyan. Foreground: 36, Background: 46
    Cyan,
    /// ANSI Color: White. Foreground: 37, Background: 47
    ///
    /// Note that this is sometimes called `silver` or `white` but we use `white` for bright white
    Gray,
    /// ANSI Color: Bright Black. Foreground: 90, Background: 100
    ///
    /// Note that this is sometimes called `light black` or `bright black` but we use `dark gray`
    DarkGray,
    /// ANSI Color: Bright Red. Foreground: 91, Background: 101
    LightRed,
    /// ANSI Color: Bright Green. Foreground: 92, Background: 102
    LightGreen,
    /// ANSI Color: Bright Yellow. Foreground: 93, Background: 103
    LightYellow,
    /// ANSI Color: Bright Blue. Foreground: 94, Background: 104
    LightBlue,
    /// ANSI Color: Bright Magenta. Foreground: 95, Background: 105
    LightMagenta,
    /// ANSI Color: Bright Cyan. Foreground: 96, Background: 106
    LightCyan,
    /// ANSI Color: Bright White. Foreground: 97, Background: 107
    /// Sometimes called `bright white` or `light white` in some terminals
    White,
    /// An RGB color.
    ///
    /// Note that only terminals that support 24-bit true color will display this correctly.
    /// Notably versions of Windows Terminal prior to Windows 10 and macOS Terminal.app do not
    /// support this.
    Rgb: struct { u8, u8, u8 },
    /// An 8-bit 256 color.
    ///
    /// See also <https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit>
    Indexed: u8,
};

comptime {
    std.debug.assert(@sizeOf(Color) == @sizeOf(u32));
}

const Modifier = packed struct(u8) {
    bold: bool,
    dim: bool,
    italic: bool,
    underlined: bool,
    slow_blink: bool,
    rapid_blink: bool,
    // reversed: bool,
    hidden: bool,
    crossed_out: bool,
};

const Cell = struct {
    symbol: u21,
    fg: Color,
    bg: Color,
    mod: Modifier,
    /// Zeroed value is to not render the cell, this allows the array to just
    /// be memset to zero to reset frame buffer
    render: bool = false,
    // x: u16,
    // y: u16,

    pub inline fn setSymbol(self: *Cell, char: u21) void {
        self.symbol = char;
    }
};

pub const Term = struct {
    tty: trm.Terminal,
    buffer: []Cell,
    size: trm.Size,

    a: std.mem.Allocator,

    pub fn init(a: std.mem.Allocator) !Term {
        const fd = try std.posix.open("/dev/tty", .{ .ACCMODE = .RDWR }, 0);
        const file = std.fs.File{ .handle = fd };

        try trm.enterAlternateScreen(file.writer());
        var tty = try trm.Terminal.init(file);

        try tty.enableRawMode();

        const size = try trm.getWindowSize(fd);

        const buffer = try a.alloc(Cell, size[0] * size[1]);

        return .{
            .tty = tty,
            .buffer = buffer,
            .size = size,
            .a = a,
        };
    }

    pub fn getCell(self: Term, x: u16, y: u16) ?*Cell {
        const i = (y * self.size[0]) + x;
        if (i >= self.buffer.len) return null;
        const ptr = &self.buffer[i];
        ptr.render = true;
        // ptr.x = x;
        // ptr.y = y;
        return ptr;
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

        var i: u16 = 0;

        var utf8 = (try std.unicode.Utf8View.init(data)).iterator();
        while (utf8.nextCodepoint()) |c| {
            if (i >= screen.w) break;

            const cell = self.getCell(screen.x + col + i, screen.y + row) orelse return;
            cell.setSymbol(c);

            i += 1;
        }
    }

    pub fn start(self: *Term, resize: bool) !void {
        if (resize) {
            self.size = try trm.getWindowSize(self.tty.f.handle);
            self.buffer = try self.a.realloc(self.buffer, self.size[0] * self.size[1]);
        }
        @memset(std.mem.asBytes(self.buffer), 0);
    }

    /// Flushes out the current buffer to the screen
    pub fn finish(self: Term) !void {
        var buf = std.ArrayList(u8).init(self.a);
        defer buf.deinit();
        const wr = buf.writer();

        // try term.clear(wr, .All);

        // var fg = Color.Reset;
        // var bg = Color.Reset;
        // var modifier = Modifier{};

        var pos: [2]u16 = .{ std.math.maxInt(u16) - 1, std.math.maxInt(u16) - 1 };
        var i: u16 = 0;
        for (self.buffer) |cell| {
            defer i += 1;
            if (!cell.render) continue;

            const y: u16 = i / self.size[0];
            const x: u16 = i % self.size[0];

            if (pos[0] + 1 == x and pos[1] == y) {
                // std.log.info("skiped a move command", .{});
            } else {
                try trm.moveTo(wr, x, y);
            }
            pos = .{ x, y };

            // TODO: check modifier is same and change update if not
            // TODO: "   " colors   "                              "

            var codepoint: [4]u8 = undefined;
            const s = try std.unicode.utf8Encode(cell.symbol, &codepoint);
            try wr.writeAll(codepoint[0..s]);
        }
        // TODO: reset all color and attris at end

        // write buffer to terminal
        try self.tty.f.writeAll(buf.items);

        // let the terminal deal with all the shit we just wrote
        try std.posix.syncfs(self.tty.f.handle);
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
};

pub const log = struct {
    var logOutputFile: ?std.fs.File = null;

    /// File ownership is still maintained by the caller and *you* must close
    // it. If you need acsess to it at a later point use `getFile`. Argument
    // can be null which removes the log file.
    pub fn setFile(f: ?std.fs.File) void {
        logOutputFile = f;
    }

    /// Gets the file used for logging if any
    pub fn getFile() ?std.fs.File {
        return logOutputFile;
    }

    pub fn toFile(
        comptime message_level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = scope;
        if (logOutputFile) |f| {
            const fmt = comptime message_level.asText() ++ ": " ++ format;
            std.fmt.format(f.writer(), fmt, args) catch {};
        }
    }

    pub fn toNull(
        comptime message_level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = message_level;
        _ = scope;
        _ = format;
        _ = args;
    }
};
