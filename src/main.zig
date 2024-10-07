const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const StringList = std.ArrayListUnmanaged(u8);

// Change this to whatever you wish for your terminal
const terminal_width = 50;
comptime {
    // The lizard must be able to fit inside the terminal
    assert(lizard_width < terminal_width);
}
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

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var args_iter: std.process.ArgIterator = try .initWithAllocator(allocator);
    defer args_iter.deinit();

    // skip the executable name
    assert(args_iter.skip());

    var words: StringList = .empty;
    defer words.deinit(allocator);

    if (args_iter.next()) |first| {
        try words.appendSlice(allocator, first);
        while (args_iter.next()) |next| {
            // arguments are typically space separated
            try words.append(allocator, ' ');
            try words.appendSlice(allocator, next);
        }
    } else {
        // no user input was supplied, use stdin instead
        const stdin = std.io.getStdIn().reader();
        while (true) {
            const byte = stdin.readByte() catch break;
            try words.append(allocator, byte);
        }
    }

    const stdout = std.io.getStdOut().writer();
    try sayWithReader(allocator, stdout, words.items);
}

fn sayWithReader(allocator: Allocator, writer: anytype, raw_input: []const u8) !void {
    const line_len = terminal_width - 4;

    const sanitized = try sanitizeInput(allocator, raw_input);
    defer allocator.free(sanitized);
    const line_broken = try lineBreakInput(allocator, sanitized, line_len);
    defer allocator.free(line_broken);

    const line_count = (line_broken.len + line_len - 1) / line_len;

    if (line_count > 0) {
        try topAndBottomPrint(writer, line_broken.len, '_');
        if (line_count == 1) {
            // Single line, easy case
            try writer.writeAll("< ");
            try writer.writeAll(line_broken);
            try writer.writeAll(" >\n");
        } else {
            // More complex, use / and | and \
            var line_number: usize = 0;
            while (line_number < line_count) : (line_number += 1) {
                const line_start: usize = line_number * line_len;
                const remainder = line_broken[line_start..];
                if (line_number == line_count - 1) {
                    const padding = line_len - remainder.len;
                    try writer.writeAll("\\ ");
                    try writer.writeAll(remainder);
                    try writer.writeByteNTimes(' ', padding);
                    try writer.writeAll(" /\n");
                } else {
                    const line = remainder[0..line_len];
                    if (line_number == 0) {
                        try writer.writeAll("/ ");
                        try writer.writeAll(line);
                        try writer.writeAll(" \\\n");
                    } else {
                        try writer.writeAll("| ");
                        try writer.writeAll(line);
                        try writer.writeAll(" |\n");
                    }
                }
            }
        }
        try topAndBottomPrint(writer, line_broken.len, '-');
    }
    try writer.writeAll(lizard);
}

fn sanitizeInput(allocator: Allocator, input: []const u8) ![]const u8 {
    var result: StringList = try .initCapacity(allocator, input.len);
    defer result.deinit(allocator);
    for (input) |byte| {
        if (std.ascii.isWhitespace(byte)) {
            result.appendAssumeCapacity(' ');
        } else if (std.ascii.isPrint(byte)) {
            result.appendAssumeCapacity(byte);
        } else {
            result.appendAssumeCapacity('?');
        }
    }
    return try result.toOwnedSlice(allocator);
}

// Doesn't actually insert newlines, just pads lines using spaces
fn lineBreakInput(allocator: Allocator, input: []const u8, line_len: usize) ![]const u8 {
    var result: StringList = .empty;
    defer result.deinit(allocator);
    var space_splitter = std.mem.tokenizeScalar(u8, input, ' ');
    var current_len: usize = 0;
    while (space_splitter.next()) |word| {
        if (current_len + 1 + word.len >= line_len) {
            // The line would be too long - split it up:
            if (word.len <= line_len) {
                const next_line_pad = line_len - current_len;
                const line_padding = next_line_pad % line_len;
                try result.appendNTimes(allocator, ' ', line_padding);
                try result.appendSlice(allocator, word);
                current_len = word.len % line_len;
            } else {
                var remaining = word;
                if (current_len > 0) {
                    const start_len = line_len - (current_len + 1);
                    try result.append(allocator, ' ');
                    try result.appendSlice(allocator, remaining[0..start_len]);
                    remaining = remaining[start_len..];
                }
                while (remaining.len > line_len) {
                    try result.appendSlice(allocator, remaining[0..line_len]);
                    remaining = remaining[line_len..];
                }
                try result.appendSlice(allocator, remaining);
                current_len = remaining.len % line_len;
            }
        } else if (current_len > 0) {
            try result.append(allocator, ' ');
            try result.appendSlice(allocator, word);
            current_len += 1 + word.len;
        } else {
            try result.appendSlice(allocator, word);
            current_len += word.len;
        }
    }
    return try result.toOwnedSlice(allocator);
}

fn topAndBottomPrint(writer: anytype, input_len: usize, symbol: u8) !void {
    const line_len = @min(terminal_width, input_len + 4);
    try writer.writeByte(' ');
    try writer.writeByteNTimes(symbol, line_len - 2);
    try writer.writeAll(" \n");
}
