const std = @import("std");

// pub const Command = struct {
//     func: *const fn (*anyopaque, std.io.AnyWriter) void,
//     data: *anyopaque,
//
//     fn run(self: Command, w: std.io.AnyWriter) void {
//         return self.func(self.data, w);
//     }
// };
// pub const MoveTo = struct {
//     x: u16,
//     y: u16,
//
//     pub fn command(self: *MoveTo) Command {
//         return .{
//             .func = MoveTo.exec,
//             .data = self,
//         };
//     }
//
//     pub fn exec(p: *anyopaque, w: std.io.AnyWriter) void {
//         const self: *MoveTo = @ptrCast(@alignCast(p));
//         moveTo(w, self.x, self.y) catch return;
//     }
// };
// test "thing" {
//     const f = std.io.getStdOut();
//
//     var move = MoveTo{ .x = 3, .y = 4 };
//
//     execute(f.writer().any(), &.{
//         move.command(),
//     });
// }
// pub fn execute(w: std.io.AnyWriter, commands: []const Command) void {
//     for (commands) |command| command.run(w);
//     // w.flush();
// }

fn ctrl(comptime c: u8) u8 {
    return c - 'a' + 1;
}

pub const Event = union(enum) {
    Key: KeyEvent,
    Resize: struct { u16, u16 },
    Timeout,
    End,
    Unknown,
};

pub const KeyModifiers = packed struct(u2) {
    pub const CTRL = KeyModifiers{ .ctrl = true };
    ctrl: bool = false,
    altr: bool = false,
};

pub const KeyEventType = enum(u8) {
    Char,
    Return,
    Backspace,
    Esc,
};

pub const KeyEvent = struct {
    modifiers: KeyModifiers = .{},
    eventtype: KeyEventType = .Char,
    /// The value of the character, just a letter or simple escape code. When
    /// `eventtype` is not equal to `.Char` then this is always 0. When it is
    /// .Char, 0 repersents a null byte.
    character: u8 = 0,
};

// const jmp = @cImport({
//     @cInclude("setjmp.h");
// });
// fn t() void {
//     var buf: jmp.jmp_buf = undefined;
//     jmp.setjmp(buf); // sets a jump point and returns 0
//     jmp.longjmp(buf, 1); // jumpts to point and returns 1 (value passed)
// }

/// If the signal handler for screen size changes has been installed
var signalHandlerInstalled = false;
/// A set of pipes to the signal handler to write to
var handleDataPipe: std.posix.fd_t = -1;

// fn handleSegfaultPosix(sig: i32, info: *const posix.siginfo_t, ctx_ptr: ?*anyopaque) callconv(.C) noreturn {
fn sigWinchHandler(_: i32, _: *const std.c.siginfo_t, _: ?*anyopaque) callconv(.C) void {
    if (handleDataPipe < 0) return;
    _ = std.posix.write(handleDataPipe, "x") catch 0;
}

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
    ///     tty.f.close();
    ///     tty.deinit();
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
        return switch (b[0]) {
            'a'...'z' => .{ .Key = .{ .character = b[0] } },
            'A'...'Z' => .{ .Key = .{ .character = b[0] } },
            '\t' => .{ .Key = .{ .character = '\t' } },
            ' ' => .{ .Key = .{ .character = ' ' } },
            '\r', '\n' => .{ .Key = .{ .eventtype = .Return } },
            // ctrl('a')...ctrl('z') => .Key(.Ctrl(b + ctrl('a') - 1)),
            // '0'...'9' => {},
            // '/' => {},
            '\x1B' => blk: {
                if (b.len < 2) break :blk .{ .Key = .{ .eventtype = .Esc } };
                switch (b[1]) {
                    '[' => {
                        // TODO: parse_csi,

                    },
                    else => {
                        // repeat the parser and add the alt modifier
                        var ev = parse(b[1..]); // todo: if this returns an error then just return Esc from this block

                        const isKey = switch (ev) {
                            .Key => true,
                            else => false,
                        };

                        if (isKey) ev.Key.modifiers.altr = true;
                        break :blk ev;
                    },
                }
            },
            else => blk: {
                // Some utf8 character I dont understand. The terminal should
                // send the whole character in one read if possible so by just
                // discarding the buffer the properly deals with it
                break :blk .Unknown;
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

pub const Size = struct { u16, u16 };

pub fn getWindowSize(fd: std.posix.fd_t) !Size {
    var win = std.mem.zeroes(std.posix.winsize);

    if (std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&win)) != 0) {
        return error.bad_ioctl;
    }
    return .{ win.ws_col, win.ws_row };
}

pub fn csi(comptime expr: []const u8) []const u8 {
    return comptime "\x1B[" ++ expr;
}

pub fn moveTo(writer: anytype, x: u16, y: u16) !void {
    try std.fmt.format(writer, csi("{};{}H"), .{ x + 1, y + 1 });
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
