const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const Chunk = @import("chunk.zig").Chunk;
const chunk_type = @import("chunk_type.zig");
const ChunkError = chunk_type.ChunkError;

pub const Png = struct {
    header: [8]u8,
    chunks: ArrayList(Chunk),
    allocator: Allocator,

    pub fn init(allocator: Allocator) Png {
        return Png{
            .header = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 }, // standrad header for all png files
            .chunks = ArrayList(Chunk).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: Png) void {
        for (self.chunks.items) |chunk| {
            chunk.deinit();
        }
        self.chunks.deinit();
    }

    pub fn tryFrom(allocator: Allocator, bytes: []const u8) ChunkError!Png {
        if (bytes.len < 8) {
            return ChunkError.PngInvalidHeader;
        }

        const standrad = [_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 };
        for (standrad, bytes[0..8]) |s, b| {
            if (s != b) {
                return ChunkError.PngInvalidHeader;
            }
        }
        // WTF i dont know why this fails when above doesn't
        // if (std.mem.eql(u8, bytes[0..8], &standrad)) {
        //     return ChunkError.PngInvalidHeader;
        // }

        var png = Png.init(allocator);
        errdefer png.deinit();
        var start: usize = 8;
        while (true) {
            if (bytes.len == start) {
                break;
            }
            const chunk = try Chunk.tryFrom(allocator, bytes[start..]);
            errdefer chunk.deinit();
            start += chunk.length + 12;
            try png.chunks.append(chunk);
            errdefer png.deinit();
        }
        return png;
    }

    pub fn appendChunk(self: *Png, chunk: Chunk) ChunkError!void {
        try self.chunks.append(chunk);
    }

    // removes the first chunk that matches the provided chunk type
    pub fn removeFirstChunk(self: *Png, chunktype: []const u8) ChunkError!Chunk {
        var index: usize = self.chunks.items.len;
        for (self.chunks.items, 0..) |chunk, i| {
            if (std.mem.eql(u8, &chunk.chunk_type.bytes, chunktype)) {
                index = i;
            }
        }
        if (index == self.chunks.items.len) {
            return ChunkError.PngChunkNotFound;
        }

        return self.chunks.orderedRemove(index);
    }

    pub fn chunkByType(self: Png, chunktype: []const u8) ?*Chunk {
        var index: usize = self.chunks.items.len;
        for (self.chunks.items, 0..) |chunk, i| {
            if (std.mem.eql(u8, &chunk.chunk_type.bytes, chunktype)) {
                index = i;
            }
        }
        if (index == self.chunks.items.len) {
            return null;
        }

        return &self.chunks.items[index];
    }

    pub fn writeToFile(self: Png, file: *const std.fs.File) !void {
        try file.writeAll(&self.header);
        for (self.chunks.items) |chunk| {
            try file.writeAll(Chunk.u32ToBytes(chunk.length));
            try file.writeAll(&chunk.chunk_type.bytes);
            try file.writeAll(chunk.data);
            try file.writeAll(Chunk.u32ToBytes(chunk.crc));
        }
    }
};

test "empty_init_deinit" {
    const allocator = std.testing.allocator;
    const png = Png.init(allocator);
    png.deinit();
}

test "try_from" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
    } ++
        [_]u8{ 0x00, 0x00, 0x00, 0x2A } ++ "RuSt" ++ "This is where your secret message will be!" ++ [_]u8{ 0xAB, 0xD1, 0xD8, 0x4E } ++
        [_]u8{ 0, 0, 0, 6 } ++ "rUSt" ++ "Hello!" ++ [_]u8{ 0xC6, 0x95, 0x54, 0x02 } ++
        [_]u8{ 0, 0, 0, 11 } ++ "TeSt" ++ "Testing png" ++ [_]u8{ 0x8D, 0x70, 0x3A, 0xD3 };

    const png = Png.tryFrom(allocator, bytes) catch unreachable;
    defer png.deinit();

    const expected = "Testing png";
    try std.testing.expectEqualStrings(expected, png.chunks.getLast().data);
}

test "append_chunk" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
    } ++
        [_]u8{ 0x00, 0x00, 0x00, 0x2A } ++ "RuSt" ++ "This is where your secret message will be!" ++ [_]u8{ 0xAB, 0xD1, 0xD8, 0x4E } ++
        [_]u8{ 0, 0, 0, 6 } ++ "rUSt" ++ "Hello!" ++ [_]u8{ 0xC6, 0x95, 0x54, 0x02 };

    const append_bytes = [_]u8{ 0, 0, 0, 11 } ++ "TeSt" ++ "Testing png" ++ [_]u8{ 0x8D, 0x70, 0x3A, 0xD3 };
    var png = Png.tryFrom(allocator, bytes) catch unreachable;
    defer png.deinit();
    const chunk = Chunk.tryFrom(allocator, append_bytes) catch unreachable;
    png.appendChunk(chunk) catch unreachable;

    const expected = "Testing png";
    try std.testing.expectEqualStrings(expected, png.chunks.getLast().data);
}

test "removeFirstChunk" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
    } ++
        [_]u8{ 0x00, 0x00, 0x00, 0x2A } ++ "RuSt" ++ "This is where your secret message will be!" ++ [_]u8{ 0xAB, 0xD1, 0xD8, 0x4E } ++
        [_]u8{ 0, 0, 0, 6 } ++ "rUSt" ++ "Hello!" ++ [_]u8{ 0xC6, 0x95, 0x54, 0x02 } ++
        [_]u8{ 0, 0, 0, 11 } ++ "TeSt" ++ "Testing png" ++ [_]u8{ 0x8D, 0x70, 0x3A, 0xD3 };

    var png = Png.tryFrom(allocator, bytes) catch unreachable;
    defer png.deinit();

    const last_type = "TeSt";
    const last = try png.removeFirstChunk(last_type);
    defer last.deinit();
    const expected = "Testing png";
    try std.testing.expectEqualStrings(expected, last.data);
}

test "chunkByType" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
    } ++
        [_]u8{ 0x00, 0x00, 0x00, 0x2A } ++ "RuSt" ++ "This is where your secret message will be!" ++ [_]u8{ 0xAB, 0xD1, 0xD8, 0x4E } ++
        [_]u8{ 0, 0, 0, 6 } ++ "rUSt" ++ "Hello!" ++ [_]u8{ 0xC6, 0x95, 0x54, 0x02 } ++
        [_]u8{ 0, 0, 0, 11 } ++ "TeSt" ++ "Testing png" ++ [_]u8{ 0x8D, 0x70, 0x3A, 0xD3 };

    const png = Png.tryFrom(allocator, bytes) catch unreachable;
    defer png.deinit();

    const expected = "Testing png";
    const found_type = "TeSt";
    const found = png.chunkByType(found_type).?;
    try std.testing.expectEqualStrings(expected, found.data);

    const not_found_type = "TEST";
    const not_found = png.chunkByType(not_found_type);
    try std.testing.expect(not_found == null);
}

test "writeToFile" {
    const allocator = std.testing.allocator;
    const bytes = [_]u8{
        137,
        80,
        78,
        71,
        13,
        10,
        26,
        10,
    } ++
        [_]u8{ 0x00, 0x00, 0x00, 0x2A } ++ "RuSt" ++ "This is where your secret message will be!" ++ [_]u8{ 0xAB, 0xD1, 0xD8, 0x4E } ++
        [_]u8{ 0, 0, 0, 6 } ++ "rUSt" ++ "Hello!" ++ [_]u8{ 0xC6, 0x95, 0x54, 0x02 } ++
        [_]u8{ 0, 0, 0, 11 } ++ "TeSt" ++ "Testing png" ++ [_]u8{ 0x8D, 0x70, 0x3A, 0xD3 };

    const png = Png.tryFrom(allocator, bytes) catch unreachable;
    defer png.deinit();

    const file = try std.fs.cwd().createFile("test.txt", .{});
    defer file.close();
    try png.writeToFile(&file);
}
