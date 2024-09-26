const std = @import("std");

const inner = @import("thermit.zig");

// pub const Event = inner.Event;
// pub const KeyEvent = inner.KeyEvent;

const exter = @cImport({
    @cInclude("thermit.h");
});

pub const Terminal = *anyopaque;

pub const ThermitError = enum(u8) {
    None = 0,
    Generic = 1,
};

// pub export fn terminalRead(terminal: Terminal, timeout: i32) !?Event {
//     const term: *inner.Terminal = @ptrCast(terminal);
//     return try term.read(timeout);
// }

pub export fn terminalEnableRawMode(terminal: Terminal) ThermitError {
    const term: *inner.Terminal = @alignCast(@ptrCast(terminal));
    term.enableRawMode() catch {
        return .Generic;
    };
    return .None;
}

pub export fn terminalDisableRawMode(terminal: Terminal) ThermitError {
    const term: *inner.Terminal = @alignCast(@ptrCast(terminal));
    term.disableRawMode() catch {
        return .Generic;
    };
    return .None;
}

pub const KeyEvent = inner.KeyEvent;

pub const EventType = enum(u8) { Key, Resize };

pub const Event = extern struct {
    type: EventType,
    data: [@max(@sizeOf(KeyEvent), @sizeOf(struct { u16, u16 }))]u8,
    // Key: KeyEvent,
    // Resize: struct { u16, u16 },
    // Timeout,
    // End,
    // Unknown,
};

// pub fn getWindowSize(fd: std.posix.fd_t) !struct { u16, u16 } {
//     var win = std.mem.zeroes(std.posix.winsize);
//
//     if (std.posix.system.ioctl(fd, std.posix.T.IOCGWINSZ, @intFromPtr(&win)) != 0) {
//         return error.bad_ioctl;
//     }
//     return .{ win.ws_col, win.ws_row };
// }

// pub fn moveTo(writer: anytype, x: u16, y: u16) !void {
//     try std.fmt.format(writer, csi("{};{}H"), .{ x + 1, y + 1 });
// }
//
// /// move down one line and moves cursor to start of line
// pub fn nextLine(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}E"), .{n});
// }
//
// /// move up one line and moves cursor to start of line
// pub fn prevLine(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}F"), .{n});
// }
//
// pub fn moveCol(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}G"), .{n + 1});
// }
//
// pub fn moveRow(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}d"), .{n + 1});
// }
//
// pub fn moveUp(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}A"), .{n});
// }
//
// pub fn moveDown(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}B"), .{n});
// }
//
// pub fn moveRight(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}C"), .{n});
// }
//
// pub fn moveLeft(writer: anytype, n: u16) !void {
//     try std.fmt.format(writer, csi("{}D"), .{n});
// }
//
// const ClearType = enum {
//     /// All cells.
//     All,
//     /// All plus history
//     Purge,
//     /// All cells from the cursor position downwards.
//     FromCursorDown,
//     /// All cells from the cursor position upwards.
//     FromCursorUp,
//     /// All cells at the cursor row.
//     CurrentLine,
//     /// All cells from the cursor position until the new line.
//     UntilNewLine,
// };
//
// pub fn clear(writer: anytype, cleartype: ClearType) !void {
//     try writer.writeAll(switch (cleartype) {
//         .All => csi("2J"),
//         .Purge => csi("3J"),
//         .FromCursorDown => csi("J"),
//         .FromCursorUp => csi("1J"),
//         .CurrentLine => csi("2K"),
//         .UntilNewLine => csi("K"),
//     });
// }
//
// pub fn savePosition(writer: anytype) !void {
//     try writer.writeAll("\x1B7");
// }
//
// pub fn restorePosition(writer: anytype) !void {
//     try writer.writeAll("\x1B8");
// }
//
// pub fn cursorHide(writer: anytype) !void {
//     try writer.writeAll(csi("?25l"));
// }
//
// pub fn cursorShow(writer: anytype) !void {
//     try writer.writeAll(csi("?25h"));
// }
//
// /// Enables Cursor Blinking
// pub fn cursorBlinkEnable(writer: anytype) !void {
//     try writer.writeAll(csi("?12h"));
// }
//
// /// Enables Cursor Blinking
// pub fn cursorBlinkDisable(writer: anytype) !void {
//     try writer.writeAll(csi("?12l"));
// }

pub const CursorStyle = inner.CursorStyle;

// pub fn setCursorStyle(writer: anytype, style: CursorStyle) !void {
//     try writer.writeAll(switch (style) {
//         .DefaultUserShape => csi("0 q"),
//         .BlinkingBlock => csi("1 q"),
//         .SteadyBlock => csi("2 q"),
//         .BlinkingUnderScore => csi("3 q"),
//         .SteadyUnderScore => csi("4 q"),
//         .BlinkingBar => csi("5 q"),
//         .SteadyBar => csi("6 q"),
//     });
// }

// pub fn enterAlternateScreen(writer: anytype) !void {
//     try writer.writeAll(csi("?1049h"));
// }
//
// pub fn leaveAlternateScreen(writer: anytype) !void {
//     try writer.writeAll(csi("?1049l"));
// }
