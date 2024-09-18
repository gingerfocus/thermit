const std = @import("std");

// lsp does not work with modules made within this package so for development
// the file is just imported
const thermit = @import("thermit.zig");
// const thermit = @import("thermit");

// const SMP_SPINNER: [&str; 4] = ["|", "/", "-", "\\"];
// const DOT_SPINNER: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

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
            try thermit.cursorHide(self.output);
            self.cursor = false;
        }

        const buf = "\x1B[2K" ++ "\r" ++ self.frame[self.frame];
        self.output.writeAll(&buf);

        self.frame += 1;
        self.frame %= self.frames.len;
    }

    pub fn finish(self: Self) !void {
        if (!self.cursor) {
            try thermit.cursorShow(self.output);
        }
        try thermit.clear(self.output, .CurrentLine);
        self.output.writeAll("Done!\n");

        // also see std.posix.AF.INET
    }
};

// impl<'a> Spinner<'a> {
//     pub fn run(self) -> std::io::Result<()> {
//         let mut i = 0usize;
//         let mut stdout = std::io::stdout().lock();
//         stdout.write(HIDE.as_bytes())?;
//         stdout.flush()?;
//         loop {
//             write!(
//                 stdout,
//                 "{}\r{}",
//                 CLEAR_LINE,
//                 self.frames[i % self.frames.len()]
//             )?;
//             stdout.flush()?;
//             std::thread::sleep(std::time::Duration::from_millis(50));
//             i += 1;
//
//             if i == 100 {
//                 break;
//             }
//         }
//         write!(stdout, "{}\n", SHOW)?;
//
//         Ok(())
//     }
// }
