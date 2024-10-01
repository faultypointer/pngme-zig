const std = @import("std");

pub const ChunkError = error{ InvalidChunkTypeByte, InvalidChunkTypeLength, OutOfMemory, ChunkInvalid, ChunkDataLengthMisMatch, ChunkCrcInvalid, PngInvalidHeader, PngChunkNotFound };

pub const ChunkType = struct {
    bytes: [4]u8,

    pub fn isReservedBitValid(self: ChunkType) bool {
        return (self.bytes[2] & 0b00100000) == 0;
    }

    pub fn isValid(self: ChunkType) bool {
        return std.ascii.isAlphabetic(self.bytes[0]) and
            std.ascii.isAlphabetic(self.bytes[1]) and
            std.ascii.isAlphabetic(self.bytes[2]) and
            std.ascii.isAlphabetic(self.bytes[3]) and
            self.isReservedBitValid();
    }

    pub fn isCritical(self: ChunkType) bool {
        return (self.bytes[0] & 0b00100000) == 0;
    }

    pub fn isPublic(self: ChunkType) bool {
        return (self.bytes[1] & 0b00100000) == 0;
    }

    pub fn isSafeToCopy(self: ChunkType) bool {
        return (self.bytes[3] & 0b00100000) != 0;
    }

    pub fn fromBytes(input_bytes: []const u8) ChunkError!ChunkType {
        var bytes = [_]u8{ 0, 0, 0, 0 };
        if (input_bytes.len != 4) {
            return ChunkError.InvalidChunkTypeLength;
        }
        for (input_bytes, 0..) |byte, i| {
            if (!std.ascii.isAlphabetic(byte)) {
                return ChunkError.InvalidChunkTypeByte;
            }
            bytes[i] = byte;
        }
        return ChunkType{
            .bytes = bytes,
        };
    }

    pub fn fromString(str: []const u8) ChunkError!ChunkType {
        if (str.len != 4) {
            return ChunkError.InvalidChunkTypeLength;
        }

        var data: [4]u8 = undefined;
        @memcpy(&data, str);
        return ChunkType.fromBytes(&data);
    }

    pub fn toString(self: ChunkType) []const u8 {
        return &self.bytes;
    }
};

test "test_chunk_type_from_bytes" {
    var expected = [4]u8{ 82, 117, 83, 116 };
    const actual = ChunkType.fromBytes(&expected) catch unreachable;
    try std.testing.expect(std.mem.eql(u8, expected[0..], &actual.bytes));
}

test "test_chunk_type_from_str" {
    var data = [4]u8{ 82, 117, 83, 116 };
    const expected = ChunkType.fromBytes(&data) catch unreachable;
    const actual = ChunkType.fromString("RuSt") catch unreachable;

    try std.testing.expectEqual(expected, actual);
}

test "test_chunk_type_is_critical" {
    const chunk = ChunkType.fromString("RuSt") catch unreachable;
    try std.testing.expect(chunk.isCritical());
}

test "test_chunk_type_is_not_critical" {
    const chunk = ChunkType.fromString("ruSt") catch unreachable;
    try std.testing.expect(!chunk.isCritical());
}

test "test_chunk_type_is_public" {
    const chunk = ChunkType.fromString("RUSt") catch unreachable;
    try std.testing.expect(chunk.isPublic());
}

test "test_chunk_type_is_not_public" {
    const chunk = ChunkType.fromString("RuSt") catch unreachable;
    try std.testing.expect(!chunk.isPublic());
}

test "test_chunk_type_is_reserved_bit_valid" {
    const chunk = ChunkType.fromString("RuSt") catch unreachable;
    try std.testing.expect(chunk.isReservedBitValid());
}

test "test_chunk_type_is_reserved_bit_invalid" {
    const chunk = ChunkType.fromString("Rust") catch unreachable;
    try std.testing.expect(!chunk.isReservedBitValid());
}

test "test_chunk_type_is_safe_to_copy" {
    const chunk = ChunkType.fromString("RuSt") catch unreachable;
    try std.testing.expect(chunk.isSafeToCopy());
}

test "test_chunk_type_is_unsafe_to_copy" {
    const chunk = ChunkType.fromString("RuST") catch unreachable;
    try std.testing.expect(!chunk.isSafeToCopy());
}

test "test_valid_chunk_is_valid" {
    const chunk = ChunkType.fromString("RuSt") catch unreachable;
    try std.testing.expect(chunk.isValid());
}

test "test_invalid_chunk_is_valid" {
    const chunk = ChunkType.fromString("Rust") catch unreachable;
    try std.testing.expect(!chunk.isValid());

    const invalidChunk = ChunkType.fromString("Ru1t");
    try std.testing.expectError(ChunkError.InvalidChunkTypeByte, invalidChunk);
}

test "test_chunk_type_string" {
    const chunk = ChunkType.fromString("RuSt") catch unreachable;
    try std.testing.expectEqualStrings(chunk.toString(), "RuSt");
}

test "test_chunk_type_trait_impls" {
    var data = [4]u8{ 82, 117, 83, 116 };
    const chunk_type_1 = ChunkType.fromBytes(&data) catch unreachable;
    const chunk_type_2 = ChunkType.fromString("RuSt") catch unreachable;
    _ = chunk_type_1.toString();
    try std.testing.expectEqual(chunk_type_1, chunk_type_2);
}
