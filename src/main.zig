const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const Io = std.Io;

const term_width = 80;
const lizard_width = 24;
const lizard =
    \\    \  _
    \\      /"\
    \\     /o o\
    \\ _\/ \   /  \/_
    \\  \\,_\  \_,//
    \\   '---.  .-'
    \\       \   \
    \\       /    \        ^
    \\      |     |        |\
    \\    .__\    /__.     | \
    \\   _//--.  .---\\_   / /
    \\    /\   \  \  /\   / /
    \\          \  \.___,/ /
    \\           \.______,/
    \\
;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len > 1) {
        // buffered STDOUT writer
        const stdout = Io.File.stdout();
        var buffer: [4096]u8 = undefined;
        var file_writer = stdout.writer(init.io, &buffer);
        const writer: *Io.Writer = &file_writer.interface;

        // main zigsay algorithm
        try say(init.gpa, writer, args[1..]);

        // flush STDOUT
        try writer.flush();
    } else {
        std.debug.print("USAGE: {s} <message>\n", .{
            if (args.len == 0) "zigsay" else args[0],
        });
        std.process.exit(1);
    }
}

// main zigsay algorithm
fn say(gpa: Allocator, writer: *Io.Writer, args: []const []const u8) !void {

    // Allow a gap for a border and whitespace
    const line_length = term_width - 4;
    const lines = try lineBreak(gpa, args, line_length);
    defer gpa.free(lines);
    defer for (lines) |line| gpa.free(line);

    switch (lines.len) {
        0 => {},
        1 => {
            // Top border of the message block
            try triple(writer, " ", '_', lines[0].len + 2, "\n");

            // Line content
            try writer.writeAll("< ");
            try writer.writeAll(lines[0]);
            try writer.writeAll(" >\n");

            // Bottom border of the message block
            try triple(writer, " ", '-', lines[0].len + 2, "\n");
        },
        else => {
            // Top border of the message block
            try triple(writer, " ", '_', term_width - 2, "\n");

            for (lines, 0..) |line, idx| {
                // Left border of the message block
                if (idx == 0) {
                    try writer.writeAll("/ ");
                } else if (idx + 1 == lines.len) {
                    try writer.writeAll("\\ ");
                } else {
                    try writer.writeAll("| ");
                }

                // Line content
                try writer.writeAll(line);

                // Padding to flush out line length
                const padding = line_length - line.len;
                try writer.splatByteAll(' ', padding);

                // Right border of the message block
                if (idx == 0) {
                    try writer.writeAll(" \\\n");
                } else if (idx + 1 == lines.len) {
                    try writer.writeAll(" /\n");
                } else {
                    try writer.writeAll(" |\n");
                }
            }

            // Bottom border of the message block
            try triple(writer, " ", '-', term_width - 2, "\n");
        },
    }

    try writer.writeAll(lizard);
}

fn triple(
    writer: *Io.Writer,
    start: []const u8,
    byte: u8,
    splat: usize,
    end: []const u8,
) !void {
    try writer.writeAll(start);
    try writer.splatByteAll(byte, splat);
    try writer.writeAll(end);
}

// simple linebreak algorithm for some number
// of arguments, and a target line length
fn lineBreak(
    gpa: Allocator,
    args: []const []const u8,
    line_length: usize,
) ![]const []const u8 {
    // Each line has at most line_length bytes
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(gpa);
    // The buffer holding an individual line
    const buffer = try gpa.alloc(u8, line_length);
    defer gpa.free(buffer);
    // The writer & current word for a line
    var writer = Io.Writer.fixed(buffer);
    var word: []const u8 = &.{};
    var idx: usize = 0;

    fsa: switch (enum { start, load }.start) {
        .start => {
            if (word.len == 0) {
                // load a word if we still have one left
                if (idx < args.len) continue :fsa .load;
            } else if (writer.end + word.len <= line_length) {
                // write out the word to the current line
                try writer.writeAll(word);

                if (idx < args.len) {
                    // write out a space after the word
                    if (writer.end + 1 < line_length) {
                        try writer.writeByte(' ');
                    }

                    // load another word
                    continue :fsa .load;
                }
            } else {
                if (word.len > line_length) {
                    // split the word to the line length
                    const len = line_length - writer.end;
                    try writer.writeAll(word[0..len]);
                    word = word[len..];
                }

                // store and clear the current line
                const line = writer.buffered();
                const dupe = try gpa.dupe(u8, line);
                try lines.append(gpa, dupe);
                writer.end = 0;

                // go back to start
                continue :fsa .start;
            }
        },
        .load => {
            // load a word
            word = args[idx];
            idx += 1;

            // go back to start
            continue :fsa .start;
        },
    }

    if (writer.end > 0) {
        // store the current line
        const line = writer.buffered();
        const dupe = try gpa.dupe(u8, line);
        try lines.append(gpa, dupe);
    }

    return try lines.toOwnedSlice(gpa);
}
