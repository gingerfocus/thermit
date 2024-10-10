const std = @import("std");

pub const Event = union(enum) {
    Key: KeyEvent,
    Resize: Size,
    Timeout,
    End,
    Unknown,
};

pub const KeyModifiers = packed struct(u8) {
    shft: bool = false,
    ctrl: bool = false,
    altr: bool = false,
    _pad: u5 = 0,

    /// Convience meathod for getting the bits
    pub fn bits(self: KeyModifiers) u8 {
        return @bitCast(self);
    }

    pub const CTRL = KeyModifiers{ .ctrl = true };
};

pub const KeyCharacter = enum(u8) {
    None = 0,
    a = 'a',
    b = 'b',
    c = 'c',
    d = 'd',
    e = 'e',
    f = 'f',
    g = 'g',
    h = 'h',
    i = 'i',
    j = 'j',
    k = 'k',
    l = 'l',
    m = 'm',
    n = 'n',
    o = 'o',
    p = 'p',
    q = 'q',
    r = 'r',
    s = 's',
    t = 't',
    u = 'u',
    v = 'v',
    w = 'w',
    x = 'x',
    y = 'y',
    z = 'z',
    A = 'A',
    B = 'B',
    C = 'C',
    D = 'D',
    E = 'E',
    F = 'F',
    G = 'G',
    H = 'H',
    I = 'I',
    J = 'J',
    K = 'K',
    L = 'L',
    M = 'M',
    N = 'N',
    O = 'O',
    P = 'P',
    Q = 'Q',
    R = 'R',
    S = 'S',
    T = 'T',
    U = 'U',
    V = 'V',
    W = 'W',
    X = 'X',
    Y = 'Y',
    Z = 'Z',
    N0 = '0',
    N1 = '1',
    N2 = '2',
    N3 = '3',
    N4 = '4',
    N5 = '5',
    N6 = '6',
    N7 = '7',
    N8 = '8',
    N9 = '9',
    Return = '\n',
    Space = ' ',
    Esc,
    Backspace,

    pub fn b(self: KeyCharacter) u8 {
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
    pub inline fn norm(c: KeyCharacter) u16 {
        return @bitCast(KeyEvent{ .character = c });
    }

    pub inline fn ctrl(c: KeyCharacter) u16 {
        const keyev = KeyEvent{
            .character = c,
            .modifiers = .{ .ctrl = true },
        };
        return @bitCast(keyev);
    }

    pub inline fn altr(c: KeyCharacter) u16 {
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
    character: KeyCharacter = .None,
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
            try std.posix.sigaction(
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

            return .{ .Resize = try getWindowSize(self.pollfds[0].fd) };
        }

        std.debug.assert(self.pollfds[0].revents == std.posix.POLL.IN);
        self.pollfds[0].revents = 0; // reset

        const readsize = try self.f.read(&bytes);
        if (readsize == 0) return .End;

        const b = bytes[0..readsize];

        return parse(b);
    }

    fn parse(b: []const u8) Event {
        return Event{
            .Key = switch (b[0]) {
                // direct parse
                'a'...'z',
                '0'...'9',
                '\t',
                ' ',
                => .{ .character = @enumFromInt(b[0]) },

                'A'...'Z' => .{
                    .character = @enumFromInt(b[0]),
                    // .modifiers = .{ .shft = true },
                },

                '\r', '\n' => .{ .character = .Return },

                ctrl('a')...ctrl('h'), // '\t' = ctrl('i'), '\n' = ctrl('j')
                ctrl('k')...ctrl('l'), // '\r' = ctrl('m')
                ctrl('n')...ctrl('z'),
                => KeyEvent{
                    .modifiers = KeyModifiers.CTRL,
                    .character = @enumFromInt('a' + b[0] - 1),
                },
                // '/' => {},
                '\x1B' => blk: {
                    if (b.len < 2) break :blk .{ .character = .Esc };
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
                0 => return .End,
                else => {
                    // Some utf8 character I dont understand. The terminal should
                    // send the whole character in one read if possible so by just
                    // discarding the buffer the properly deals with it
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
            // termios.iflag.IXON = false;

            // termios.oflag.OPOST = false;

            termios.lflag.ECHO = false;
            termios.lflag.ECHONL = false;
            // setermios to non-cannonicle mode: input is not buffered on new lines or parsed
            // by termioserminal
            termios.lflag.ICANON = false;
            termios.lflag.ISIG = false;
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
    return .{ .x = win.ws_col, .y = win.ws_row };
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
