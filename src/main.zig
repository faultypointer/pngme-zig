const std = @import("std");
const stdout = std.io.getStdOut().writer();
const ArgIterator = std.process.ArgIterator;

const ChunkType = @import("chunk_type.zig").ChunkType;
const ChunkError = @import("chunk_type.zig").ChunkError;
const Chunk = @import("chunk.zig").Chunk;
const Png = @import("png.zig").Png;

const Command = enum {
    encode,
    decode,
    remove,
};

pub fn main() !void {
    var buffer: [1024]u8 = undefined;
    for (0..buffer.len) |i| {
        buffer[i] = 0;
    }
    var fba = std.heap.FixedBufferAllocator.init(&buffer);
    const allocator = fba.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // skip the first arg (program name)
    _ = args.skip();
    if (args.next()) |arg| {
        var opt: Command = undefined;
        if (std.meta.stringToEnum(Command, arg)) |val| {
            opt = val;
            switch (val) {
                .encode => try encode(&args),
                .decode => try decode(&args),
                .remove => try remove(&args),
            }
        } else {
            try printHelpMessage("unknown command");
        }
        return;
    }
    try printHelpMessage("");
}

fn encode(args: *ArgIterator) !void {
    // get all the options
    var file: std.fs.File = undefined;
    var chunk_type: ChunkType = undefined;
    var chunk: Chunk = undefined;
    var output_file: ?std.fs.File = null;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // get the options
    if (args.next()) |arg| {
        file = try std.fs.cwd().openFile(arg, .{ .mode = .read_write });
    } else {
        try printEncodeHelpMessage();
        return;
    }
    defer file.close();
    if (args.next()) |arg| {
        chunk_type = try ChunkType.fromString(arg);
    } else {
        try printEncodeHelpMessage();
        return;
    }
    if (args.next()) |arg| {
        chunk = try Chunk.init(allocator, chunk_type, arg);
        errdefer chunk.deinit();
    } else {
        try printEncodeHelpMessage();
        return;
    }
    if (args.next()) |arg| {
        output_file = try std.fs.cwd().createFile(arg, .{});
    }
    const stat = try file.stat();
    const data_buffer = try file.readToEndAlloc(allocator, stat.size);

    // for (data_buffer, 0..) |byte, i| {
    //     try stdout.print("{} ", .{byte});
    //     if (i == 7) {
    //         break;
    //     }
    // }

    var png = try Png.tryFrom(allocator, data_buffer);
    defer png.deinit();
    try png.appendChunk(chunk);

    if (output_file) |exists| {
        try png.writeToFile(&exists);
    } else {
        try file.seekTo(0);
        try png.writeToFile(&file);
    }
    // try stdout.print("{s}\n{s}\nread_len: {}\n", .{ chunk_type.bytes, chunk.data, data_buffer.len });
}
fn decode(args: *ArgIterator) !void {
    var file: std.fs.File = undefined;
    var chunk_type: ChunkType = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // get the options
    if (args.next()) |arg| {
        file = try std.fs.cwd().openFile(arg, .{});
    } else {
        try printDecodeHelpMessage();
        return;
    }
    defer file.close();
    if (args.next()) |arg| {
        chunk_type = try ChunkType.fromString(arg);
    } else {
        try printDecodeHelpMessage();
        return;
    }
    const stat = try file.stat();
    const data_buffer = try file.readToEndAlloc(allocator, stat.size);

    // for (data_buffer, 0..) |byte, i| {
    //     try stdout.print("{} ", .{byte});
    //     if (i == 7) {
    //         break;
    //     }
    // }

    const png = try Png.tryFrom(allocator, data_buffer);
    defer png.deinit();

    const chunk = png.chunkByType(&chunk_type.bytes);
    if (chunk) |exists| {
        try stdout.print("Decoded Message: {s}\n", .{exists.data});
    } else {
        try stdout.print("No secret message is found in the given file.\n", .{});
    }
}
fn remove(args: *ArgIterator) !void {
    var file: std.fs.File = undefined;
    var chunk_type: ChunkType = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // get the options
    if (args.next()) |arg| {
        file = try std.fs.cwd().openFile(arg, .{ .mode = .read_write });
    } else {
        try printRemoveHelpMessage();
        return;
    }
    defer file.close();
    if (args.next()) |arg| {
        chunk_type = try ChunkType.fromString(arg);
    } else {
        try printRemoveHelpMessage();
        return;
    }
    const stat = try file.stat();
    const data_buffer = try file.readToEndAlloc(allocator, stat.size);

    // for (data_buffer, 0..) |byte, i| {
    //     try stdout.print("{} ", .{byte});
    //     if (i == 7) {
    //         break;
    //     }
    // }

    var png = try Png.tryFrom(allocator, data_buffer);
    defer png.deinit();

    if (png.removeFirstChunk(&chunk_type.bytes)) |chunk| {
        try file.seekTo(0);
        try png.writeToFile(&file);
        try file.setEndPos(try file.getPos());
        try stdout.print("Removed the following secret message from the file.\n{s}\n", .{chunk.data});
    } else |err| {
        if (err == ChunkError.PngChunkNotFound) {
            try stdout.print("No chunk with given type found.\n", .{});
        } else {
            return err;
        }
    }
}
fn printHelpMessage(err_msg: []const u8) !void {
    if (err_msg.len > 0) {
        try stdout.print("error: {s}\n", .{err_msg});
    }
    try stdout.print("Usage: pngme <COMMAND>\n\n", .{});
    try stdout.print("Commands: \n", .{});
    try stdout.print("  encode: \t encodes the given message into the png file.\n", .{});
    try stdout.print("  decode: \t decodes the message from the png file.\n", .{});
    try stdout.print("  remove: \t removes the encoded message from the png file.\n", .{});
}

pub fn printEncodeHelpMessage() !void {
    try stdout.print(
        \\Usage: pngme encode <FILE> <CHUNK_TYPE> <MESSAGE> [OUTPUT_FILE]\n
    , .{});
}

pub fn printDecodeHelpMessage() !void {
    try stdout.print(
        \\Usage: pngme decode <FILE> <CHUNK_TYPE> \n
    , .{});
}

pub fn printRemoveHelpMessage() !void {
    try stdout.print(
        \\Usage: pngme remove <FILE> <CHUNK_TYPE> \n
    , .{});
}
