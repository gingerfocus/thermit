const std = @import("std");

pub const Event = union(enum) {
    Key: KeyEvent,
    Resize,
    Timeout,
    End,
    Unknown,
};

pub const KeyModifiers = packed struct(u8) {
    shft: bool = false,
    ctrl: bool = false,
    altr: bool = false,
    supr: bool = false,
    fnky: bool = false,
    _pad: u3 = 0,

    /// Convience meathod for getting the bits
    pub fn bits(self: KeyModifiers) u8 {
        return @bitCast(self);
    }

    pub const CTRL = KeyModifiers{ .ctrl = true };
};

pub const KeyCharacter = u8;

// https://www.ascii-code.com/
pub const KeySymbol = enum(u8) {
    None = 0,
    // 1...7 - UNUSED
    Backspace = 8,
    Tab = '\t', // 9
    Return = '\n', // 10, \r = 13
    // 11...26 - UNUSED
    Esc = 27,
    /// 28...31 - UNUSED
    Space = ' ', // 32
    // 33...126 - printable data
    // 127 - DEL
    // 128...255 - UNUSED

    pub fn toBits(self: KeySymbol) KeyCharacter {
        return @intFromEnum(self);
    }
};

/// Function for casting events into bits to be matched on. You could use these
/// as is but it is recomended to rename them to be shorter in your scope.
/// ```zig
/// const norm = thr.keys.norm;
/// const ctrl = thr.keys.ctrl;
/// const altr = thr.keys.altr;
/// ```
/// OR
/// ```zig
/// usingnamespace thr.keys;
/// ```
/// You can then do something like:
/// ```zig
/// const key: KeyEvent = ...;
/// switch (thr.keys.bits(key)) {
///     norm(.q), ctrl(.c) => { ... },
///     norm(.Enter), => { ... },
///     else => {},
/// }
/// ```
pub const keys = struct {
    pub inline fn norm(c: u8) u16 {
        return @bitCast(KeyEvent{ .character = c });
    }

    pub inline fn ctrl(c: u8) u16 {
        const keyev = KeyEvent{
            .character = c,
            .modifiers = .{ .ctrl = true },
        };
        return @bitCast(keyev);
    }

    pub inline fn altr(c: u8) u16 {
        const keyev = KeyEvent{
            .character = c,
            .modifiers = .{ .altr = true },
        };
        return @bitCast(keyev);
    }

    pub inline fn bits(ev: KeyEvent) u16 {
        return @bitCast(ev);
    }
};

pub const KeyEvent = packed struct(u16) {
    character: KeyCharacter = KeySymbol.None.toBits(),
    modifiers: KeyModifiers = .{},

    // pub fn eql(lhs: KeyEvent, rhs: KeyEvent) bool { }
};

// ---------------------------- Local Helpers-----------------------------------

/// If the signal handler for screen size changes has been installed
var signalHandlerInstalled = false;
/// A set of pipes to the signal handler to write to
var handleDataPipe: std.posix.fd_t = -1;

// fn (sig: i32, info: *const posix.siginfo_t, ctx_ptr: ?*anyopaque) callconv(.C) noreturn {
fn sigWinchHandler(sig: i32, _: *const std.posix.siginfo_t, _: ?*anyopaque) callconv(.C) void {
    std.debug.assert(sig == std.posix.SIG.WINCH);

    if (handleDataPipe < 0) return;
    _ = std.posix.write(handleDataPipe, "x") catch 0;
}

fn ctrl(comptime c: u8) u8 {
    return c - 'a' + 1;
}

// -----------------------------------------------------------------------------

pub const Terminal = struct {
    /// the file handle of this terminal, it is perfectly fine to use this for
    /// anything
    f: std.fs.File,

    /// used for restoreing the terminal after raw mode
    oldtermios: ?std.posix.termios = null,

    pollfds: [2]std.posix.pollfd,

    /// Creates a new terminal, importantly does not take ownership of the file,
    /// it is always valid to acsess it but it is still required to close it
    /// independently of this structure. This is done so if you pass
    /// `std.io.getStdErr` (which is the most common use case) to this it does not
    /// try to close it.
    ///
    /// If you dont want this (possibly from opening "/dev/tty") you can just
    /// do:
    /// ```zig
    /// defer {
    ///     tty.deinit();
    ///     tty.f.close();
    /// }
    /// ```
    pub fn init(f: std.fs.File) !Terminal {
        // install the global signal handler
        if (!signalHandlerInstalled) {
            signalHandlerInstalled = true;

            // var old = std.mem.zeroes(std.posix.Sigaction);
            std.posix.sigaction(
                std.posix.SIG.WINCH,
                &std.posix.Sigaction{
                    .handler = .{ .sigaction = sigWinchHandler },
                    .mask = std.posix.empty_sigset,
                    .flags = (std.posix.SA.SIGINFO | std.posix.SA.RESTART),
                },
                null,
            );
        }
        if (handleDataPipe >= 0) return error.Occupied;

        const pipe = try std.posix.pipe();
        handleDataPipe = pipe[1];

        const pollfds: [2]std.posix.pollfd = .{
            .{ .fd = f.handle, .events = std.posix.POLL.IN, .revents = 0 },
            .{ .fd = pipe[0], .events = std.posix.POLL.IN, .revents = 0 },
        };

        return .{ .f = f, .pollfds = pollfds };
    }

    pub fn deinit(self: Terminal) void {
        // clean up our mess, signal handler continues to run with this
        std.posix.close(handleDataPipe);
        handleDataPipe = -1;

        std.posix.close(self.pollfds[1].fd);
    }

    /// timeout: time in miliseconds to wait for a read
    pub fn read(self: *Terminal, timeout: i32) !Event {
        const r = try std.posix.poll(&self.pollfds, timeout);
        if (r == 0) return .Timeout;

        var bytes: [8]u8 = .{0} ** 8;

        if (self.pollfds[1].revents == std.posix.POLL.IN) {
            const rs = try std.posix.read(self.pollfds[1].fd, &bytes);

            std.debug.assert(std.mem.eql(u8, bytes[0..rs], "x"));
            std.debug.assert(self.pollfds[1].revents == std.posix.POLL.IN);

            self.pollfds[1].revents = 0; // reset

            return .{ .Resize = {} };
        }

        std.debug.assert(self.pollfds[0].revents == std.posix.POLL.IN);
        self.pollfds[0].revents = 0; // reset

        const readsize = try self.f.read(&bytes);
        if (readsize == 0) return .End;

        const b = bytes[0..readsize];

        return parse(b);
    }

    fn parse(b: []const u8) Event {
        const Parse = struct {
            fn toCtrl(c: u8) KeyEvent {
                return KeyEvent{
                    .modifiers = KeyModifiers.CTRL,
                    .character = 'a' + c - 1,
                };
            }
        };

        return Event{
            .Key = switch (b[0]) {
                0 => return .End,

                ctrl('a')...ctrl('g'), // 1...7
                => Parse.toCtrl(b[0]),

                8 => .{ .character = KeySymbol.Backspace.toBits() },

                '\t', // 9
                => .{ .character = KeySymbol.Tab.toBits() },

                '\n', // 10
                => .{ .character = KeySymbol.Return.toBits() },

                ctrl('k'), // 11
                ctrl('l'), // 12
                => Parse.toCtrl(b[0]),

                '\r', // 13
                => .{ .character = KeySymbol.Return.toBits() },

                ctrl('n')...ctrl('z'), // 14..26
                => Parse.toCtrl(b[0]),

                '\x1B' => blk: { // 27
                    if (b.len < 2) break :blk .{ .character = KeySymbol.Esc.toBits() };
                    switch (b[1]) {
                        '[' => {
                            // TODO: parse_csi,
                            return .Unknown;
                        },
                        else => {
                            // repeat the parser and add the alt modifier
                            var ev = parse(b[1..]); // todo: if this returns an error then just return Esc from this block

                            switch (ev) {
                                .Key => |*key| key.modifiers.altr = true,
                                else => {},
                            }
                            return ev;
                        },
                    }
                },
                28...31 => {
                    std.log.info("unknown character code: ({d})", .{b});
                    return .Unknown;
                },
                ' ' => .{ .character = KeySymbol.Space.toBits() },
                // direct parse
                // printable data, you should be able to figure these out big boy
                33...126 => .{ .character = b[0] },
                127 => .{ .character = KeySymbol.Backspace.toBits() },
                128...255 => {
                    std.log.info("unknown character code: ({d})", .{b});
                    return .Unknown;
                },
            },
        };
    }

    pub fn enableRawMode(t: *Terminal) !void {
        if (t.oldtermios != null) return;
        // get the mode prior to switching so we can revert to it
        var termios = try std.posix.tcgetattr(t.f.handle);
        const oldmode = termios;

        // Adapted from musl-libc
        {
            // useful source on what these flags do
            // https://www.man7.org/linux/man-pages/man3/termios.3.html

            // termios.iflag.IGNBRK = false;
            // termios.iflag.BRKINT = false;
            // termios.iflag.PARMRK = false;
            // termios.iflag.ISTRIP = false;
            // termios.iflag.INLCR = false;
            // termios.iflag.IGNCR = false;
            termios.iflag.ICRNL = false;
            termios.iflag.IXON = false; // disable ^S/^Q special handling

            // termios.oflag.OPOST = false;

            termios.lflag.ECHO = false;
            termios.lflag.ECHONL = false;
            // setermios to non-cannonicle mode: input is not buffered on new lines or parsed
            // by termioserminal
            termios.lflag.ICANON = false;
            termios.lflag.ISIG = false; // disable ^C/^Z special handling
            termios.lflag.IEXTEN = false;


            // termios.cflag.PARENB = false;
            // termios.cflag.CSIZE = .CS8;

            // allow kernal to send as few as 1 character on a (sucsessful) read
            termios.cc[@as(usize, @intFromEnum(std.posix.V.MIN))] = 1;
            // allow no time delay between kernal sending reads
            termios.cc[@as(usize, @intFromEnum(std.posix.V.TIME))] = 0;
        }

        try std.posix.tcsetattr(t.f.handle, .NOW, termios);

        t.oldtermios = oldmode;
    }

    pub fn disableRawMode(t: *Terminal) !void {
        if (t.oldtermios) |termios| {
            try std.posix.tcsetattr(t.f.handle, .NOW, termios);
            t.oldtermios = null;
        }
    }
};

pub const Size = struct { x: u16, y: u16 };

pub fn getWindowSize(fd: std.posix.fd_t) !Size {
    var win = std.mem.zeroes(std.posix.winsize);

    if (std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&win)) != 0) {
        return error.bad_ioctl;
    }
    return .{ .x = win.col, .y = win.row };
}

pub fn csi(comptime expr: []const u8) []const u8 {
    return comptime "\x1B[" ++ expr;
}

pub fn moveTo(writer: anytype, x: u16, y: u16) !void {
    try std.fmt.format(writer, csi("{};{}H"), .{ y + 1, x + 1 });
}

/// move down one line and moves cursor to start of line
pub fn nextLine(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}E"), .{n});
}

/// move up one line and moves cursor to start of line
pub fn prevLine(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}F"), .{n});
}

pub fn moveCol(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}G"), .{n + 1});
}

pub fn moveRow(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}d"), .{n + 1});
}

pub fn moveUp(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}A"), .{n});
}

pub fn moveDown(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}B"), .{n});
}

pub fn moveRight(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}C"), .{n});
}

pub fn moveLeft(writer: anytype, n: u16) !void {
    try std.fmt.format(writer, csi("{}D"), .{n});
}

const ClearType = enum {
    /// All cells.
    All,
    /// All plus history
    Purge,
    /// All cells from the cursor position downwards.
    FromCursorDown,
    /// All cells from the cursor position upwards.
    FromCursorUp,
    /// All cells at the cursor row.
    CurrentLine,
    /// All cells from the cursor position until the new line.
    UntilNewLine,
};

pub fn clear(writer: anytype, cleartype: ClearType) !void {
    try writer.writeAll(switch (cleartype) {
        .All => csi("2J"),
        .Purge => csi("3J"),
        .FromCursorDown => csi("J"),
        .FromCursorUp => csi("1J"),
        .CurrentLine => csi("2K"),
        .UntilNewLine => csi("K"),
    });
}

pub fn savePosition(writer: anytype) !void {
    try writer.writeAll("\x1B7");
}

pub fn restorePosition(writer: anytype) !void {
    try writer.writeAll("\x1B8");
}

pub fn cursorHide(writer: anytype) !void {
    try writer.writeAll(csi("?25l"));
}

pub fn cursorShow(writer: anytype) !void {
    try writer.writeAll(csi("?25h"));
}

/// Enables Cursor Blinking
pub fn cursorBlinkEnable(writer: anytype) !void {
    try writer.writeAll(csi("?12h"));
}

/// Enables Cursor Blinking
pub fn cursorBlinkDisable(writer: anytype) !void {
    try writer.writeAll(csi("?12l"));
}

pub const CursorStyle = enum {
    /// Default cursor shape configured by the user.
    DefaultUserShape,
    /// A blinking block cursor shape (■).
    BlinkingBlock,
    /// A non blinking block cursor shape (inverse of `BlinkingBlock`).
    SteadyBlock,
    /// A blinking underscore cursor shape(_).
    BlinkingUnderScore,
    /// A non blinking underscore cursor shape (inverse of `BlinkingUnderScore`).
    SteadyUnderScore,
    /// A blinking cursor bar shape (|)
    BlinkingBar,
    /// A steady cursor bar shape (inverse of `BlinkingBar`).
    SteadyBar,
};

pub fn setCursorStyle(writer: anytype, style: CursorStyle) !void {
    try writer.writeAll(switch (style) {
        .DefaultUserShape => csi("0 q"),
        .BlinkingBlock => csi("1 q"),
        .SteadyBlock => csi("2 q"),
        .BlinkingUnderScore => csi("3 q"),
        .SteadyUnderScore => csi("4 q"),
        .BlinkingBar => csi("5 q"),
        .SteadyBar => csi("6 q"),
    });
}

pub fn enterAlternateScreen(writer: anytype) !void {
    try writer.writeAll(csi("?1049h"));
}

pub fn leaveAlternateScreen(writer: anytype) !void {
    try writer.writeAll(csi("?1049l"));
}

// const jmp = @cImport({
//     @cInclude("setjmp.h");
// });
// fn t() void {
//     var buf: jmp.jmp_buf = undefined;
//     jmp.setjmp(buf); // sets a jump point and returns 0
//     jmp.longjmp(buf, 1); // jumpts to point and returns 1 (value passed)
// }

comptime {
    std.debug.assert(@sizeOf(Color) == @sizeOf(u32));

    // var color: Color = undefined;
    // @memset(std.mem.asBytes(&color), 0);
    // std.debug.assert(color == .Reset);
}

/// Adapted from ratatui
pub const Color = union(enum(u8)) {
    /// Resets the terminal color.
    Reset = 0,
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

    pub fn writeSequence(self: Color, wr: std.io.AnyWriter, ctype: ColorType) !void {
        // fg = 38; color | reset = 39
        // bg = 48; color | reset = 49
        // ul = 58; color | reset = 59
        //
        // colors:
        // - 5;[1-15]
        // user defined colors
        // - 2;{r};{g};{b}

        // set color -        esc code   set bg     color11   color cmd
        //     return "\x1B[" ++ "48;" ++ "5;11" ++ "m";

        // try writer.writeAll("\x1B[" ++ "48;" ++ "5;11" ++ "m");
        //
        // // reset color -      esc code  reset bg  color cmd
        // try writer.writeAll("\x1B[" ++ "49" ++ "m");

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
    }

    pub fn toRgb(self: Color) struct { u8, u8, u8 } {
        return switch (self) {
            .Black => .{ 0, 0, 0 },
            .DarkGrey => .{ 128, 128, 128 },
            .Red => .{ 255, 85, 85 },
            .DarkRed => .{ 128, 0, 0 },
            .Green => .{ 85, 255, 85 },
            .DarkGreen => .{ 0, 128, 0 },
            .Yellow => .{ 255, 255, 85 },
            .DarkYellow => .{ 128, 128, 0 },
            .Blue => .{ 85, 85, 255 },
            .DarkBlue => .{ 0, 0, 128 },
            .Magenta => .{ 255, 85, 255 },
            .DarkMagenta => .{ 128, 0, 128 },
            .Cyan => .{ 85, 255, 255 },
            .DarkCyan => .{ 0, 128, 128 },
            .White => .{ 255, 255, 255 },
            .Grey => .{ 192, 192, 192 },
            .Rgb => |rgb| rgb,
            // .AnsiValue => |n| {
            //     // 16-231: 6x6x6 color cube, 232-255: grayscale ramp
            //     if (n < 16) {
            //         // Standard colors, fallback to a basic palette
            //         const table = [_][3]u8{
            //             .{ 0, 0, 0 }, // 0: black
            //             .{ 128, 0, 0 }, // 1: red
            //             .{ 0, 128, 0 }, // 2: green
            //             .{ 128, 128, 0 }, // 3: yellow
            //             .{ 0, 0, 128 }, // 4: blue
            //             .{ 128, 0, 128 }, // 5: magenta
            //             .{ 0, 128, 128 }, // 6: cyan
            //             .{ 192, 192, 192 }, // 7: white (light gray)
            //             .{ 128, 128, 128 }, // 8: bright black (dark gray)
            //             .{ 255, 85, 85 }, // 9: bright red
            //             .{ 85, 255, 85 }, // 10: bright green
            //             .{ 255, 255, 85 }, // 11: bright yellow
            //             .{ 85, 85, 255 }, // 12: bright blue
            //             .{ 255, 85, 255 }, // 13: bright magenta
            //             .{ 85, 255, 255 }, // 14: bright cyan
            //             .{ 255, 255, 255 }, // 15: bright white
            //         };
            //         return table[n];
            //     } else if (n >= 16 and n <= 231) {
            //         const idx = n - 16;
            //         const r = @as(u8, @intCast((idx / 36) % 6));
            //         const g = @as(u8, @intCast((idx / 6) % 6));
            //         const b = @as(u8, @intCast(idx % 6));
            //         return .{
            //             @as(u8, r * 51),
            //             @as(u8, g * 51),
            //             @as(u8, b * 51),
            //         };
            //     } else if (n >= 232 and n <= 255) {
            //         const gray = @as(u8, 8 + (n - 232) * 10);
            //         return .{ gray, gray, gray };
            //     } else {
            //         return .{ 0, 0, 0 };
            //     }
            // },
            .Reset => .{ 0, 0, 0 },
            else => .{ 0, 0, 0 },
        };
    }
};
