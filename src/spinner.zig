const std = @import("std");
const thr = @import("thermit");

pub const SMP_SPINNER: [4]u8 = .{ '|', "/", "-", '\\' };
pub const DOT_SPINNER: [10]u8 = .{ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" };

pub const Spinner = struct {
    frames: []const u8,
    output: std.io.AnyWriter = std.io.getStdErr(),

    frame: usize = 0,

    /// true when the cursor is visable
    cursor: bool = true,

    const Self = @This();

    /// Steps the animation 1 frame
    pub fn step(self: Self) !void {
        if (self.cursor) {
            try thr.cursorHide(self.output);
            self.cursor = false;
        }

        const buf = "\x1B[2K" ++ "\r" ++ self.frame[self.frame];
        self.output.writeAll(&buf);

        self.frame += 1;
        self.frame %= self.frames.len;
    }

    pub fn finish(self: Self) !void {
        if (!self.cursor) {
            try thr.cursorShow(self.output);
        }
        try thr.clear(self.output, .CurrentLine);
        self.output.writeAll("Done!\n");

        // also see std.posix.AF.INET
    }
};
