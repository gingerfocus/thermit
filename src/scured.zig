pub const thermit = @import("thermit");

const std = @import("std");
const trm = thermit;

// pub const FrameBuffers = std.AutoArrayHashMapUnmanaged(
//     Term.Screen,
//     std.ArrayListUnmanaged(u8),
// );

/// Adapted from ratatui
const Color = union(enum) {
    /// Resets the terminal color.
    Reset,

    /// Black color.
    Black,

    /// Dark grey color.
    DarkGrey,

    /// Light red color.
    Red,

    /// Dark red color.
    DarkRed,

    /// Light green color.
    Green,

    /// Dark green color.
    DarkGreen,

    /// Light yellow color.
    Yellow,

    /// Dark yellow color.
    DarkYellow,

    /// Light blue color.
    Blue,

    /// Dark blue color.
    DarkBlue,

    /// Light magenta color.
    Magenta,

    /// Dark magenta color.
    DarkMagenta,

    /// Light cyan color.
    Cyan,

    /// Dark cyan color.
    DarkCyan,

    /// White color.
    White,

    /// Grey color.
    Grey,

    /// An RGB color. See [RGB color model](https://en.wikipedia.org/wiki/RGB_color_model) for more info.
    ///
    /// Most UNIX terminals and Windows 10 supported only.
    /// See [Platform-specific notes](enum.Color.html#platform-specific-notes) for more info.
    Rgb: struct { u8, u8, u8 },

    /// An ANSI color. See [256 colors - cheat sheet](https://jonasjacek.github.io/colors/) for more info.
    ///
    /// Most UNIX terminals and Windows 10 supported only.
    /// See [Platform-specific notes](enum.Color.html#platform-specific-notes) for more info.
    AnsiValue: u8,

    const ColorType = enum {
        Foreground,
        Background,
        Underline,

        fn indicator(self: ColorType) u8 {
            return switch (self) {
                .Foreground => 38,
                .Background => 48,
                .Underline => 58,
            };
        }
    };

    // fn escColor(comptime n: u8, ctype: ColorType) []const u8 {
    //     _ = n; // autofix
    //     _ = ctype; // autofix
    //
    // set color -        esc code   set bg     color11   color cmd
    //     return "\x1B[" ++ "48;" ++ "5;11" ++ "m";
    // }

    pub fn writeSequence(self: Color, wr: std.io.AnyWriter, ctype: ColorType) !void {
        // fg = 38; color | reset = 39
        // bg = 48; color | reset = 49
        // ul = 58; color | reset = 59
        //
        // colors:
        // - 5;[1-15]
        // user defined colors
        // - 2;{r};{g};{b}

        try wr.writeAll("\x1B[");

        if (self == .Reset) {
            try std.fmt.format(wr, "{}", .{ctype.indicator() + 1});
        } else {
            try std.fmt.format(wr, "{};", .{ctype.indicator()});
            const color = switch (self) {
                .Black => "5;0",
                .DarkGrey => "5;8",
                .Red => "5;9",
                .DarkRed => "5;1",
                .Green => "5;10",
                .DarkGreen => "5;2",
                .Yellow => "5;11",
                .DarkYellow => "5;3",
                .Blue => "5;12",
                .DarkBlue => "5;4",
                .Magenta => "5;13",
                .DarkMagenta => "5;5",
                .Cyan => "5;14",
                .DarkCyan => "5;6",
                .White => "5;15",
                .Grey => "5;7",
                // Color::Rgb { r, g, b } => write!(f, "2;{r};{g};{b}"),
                .Rgb => @panic("todo"),
                .AnsiValue => @panic("todo"), // 5;{n}
                .Reset => unreachable,
            };
            try wr.writeAll(color);
        }

        try wr.writeAll("m");

        // try writer.writeAll("\x1B[" ++ "48;" ++ "5;11" ++ "m");
        //
        // // reset color -      esc code  reset bg  color cmd
        // try writer.writeAll("\x1B[" ++ "49" ++ "m");
    }
};

comptime {
    std.debug.assert(@sizeOf(Color) == @sizeOf(u32));

    // var color: Color = undefined;
    // @memset(std.mem.asBytes(&color), 0);
    // std.debug.assert(color == .Reset);
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

        // HACK: zeroing color is bad for many reasons, this however fixes the problem kinda
        ptr.fg = .Reset;
        ptr.bg = .Reset;
        return ptr;
    }

    pub fn getScreenCell(self: Term, screen: Screen, x: u16, y: u16) ?*Cell {
        std.debug.assert(screen.x <= self.size[0]);
        std.debug.assert(screen.y <= self.size[1]);
        std.debug.assert(x <= screen.w);
        std.debug.assert(y <= screen.h);

        return self.getCell(screen.x + x, screen.y + y);
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

    pub fn writeBuffer(self: Term, screen: Screen, x: u16, y: u16, buffer: []const u8) void {
        var col: u16 = x;
        for (buffer) |ch| {
            if (!(col < screen.w)) return;

            const cell = self.getScreenCell(screen, col, y) orelse return;
            cell.setSymbol(ch);

            col += 1;
        }
    }

    pub const draw = @compileError(
        \\Function `draw` is depricated, consider using `getScreenCell` in a
        \\loop or `writeBuffer` if that is what you really need
    );

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

        var fg = Color.Reset;
        var bg = Color.Reset;
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
        comptime message_level: std.log.Level,
        comptime scope: @TypeOf(.enum_literal),
        comptime format: []const u8,
        args: anytype,
    ) void {
        _ = scope;
        if (logOutputFile) |f| {
            const level = comptime levelToText(message_level);
            const fmt = level ++ ": " ++ format;
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
