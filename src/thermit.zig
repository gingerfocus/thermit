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
    End,
    Key: KeyEvent,
    Timeout,
    // Resize: struct { u16, u16 },
};

pub const KeyEvent = union(enum) {
    Char: u8,
    Ctrl: u8,
    Space,
    Return,
    Backspace,
    Tab,
    Esc,
};

pub const Terminal = struct {
    /// the file handle of this terminal, it is perfectly fine to use this for
    /// anything
    f: std.fs.File,

    /// used for restoreing the terminal after raw mode
    oldtermios: ?std.posix.termios = null,

    /// timeout: time in miliseconds to wait for a read
    pub fn read(self: Terminal, timeout: i32) !Event {
        var fds: [1]std.posix.pollfd = .{
            std.posix.pollfd{
                .fd = self.f.handle,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        const r = try std.posix.poll(&fds, timeout);
        if (r == 0) return .Timeout;

        std.debug.assert(fds[0].revents == std.posix.POLL.IN);

        var b: [1]u8 = undefined;
        const readsize = try self.f.read(&b);
        if (readsize == 0) return .End;

        return switch (b[0]) {
            'a'...'z' => .Key(.Char(b)),
            'A'...'Z' => .Key(.Char(b)),
            '\t' => .Key(.Tab),
            ' ' => .Key(.Space),
            '\r', '\n' => .Key(.Return),
            // ctrl('a')...ctrl('z') => .Key(.Ctrl(b + ctrl('a') - 1)),
            // '0'...'9' => {},
            // '/' => {},
            // '\x1B' => {
            //     // if (b.len < 2) { // esc
            //     //     clearSearch(state);
            //     //     state.repeat = 1;
            //     //     continue;
            //     // }
            //     //
            //     // switch (b[1]) {
            //     //     '[' => {}, // TODO: parse_csi,
            //     //     else => {
            //     //         // repeat the parser, if it produces a key add the alt modifier else ignore `b1`
            //     //     },
            //     // }
            // },
            else => {
                // Some utf8 character I dont understand. The terminal should
                // send the whole character in one read if possible so by just
                // discarding the buffer the properly deals with it
                error.Unknown;
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

pub fn getWindowSize(fd: std.posix.fd_t) !struct { u16, u16 } {
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
