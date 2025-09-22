const std = @import("std");
const io = @import("io.zig");

pub const MetadataError = error{
    InvalidFormat,
    OutOfMemory,
} || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.File.SeekError;

pub const WavMetadata = struct {
    title: ?[]u8 = null,
    artist: ?[]u8 = null,
    album: ?[]u8 = null,
    date: ?[]u8 = null,
    genre: ?[]u8 = null,
    comment: ?[]u8 = null,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        if (self.title) |title| allocator.free(title);
        if (self.artist) |artist| allocator.free(artist);
        if (self.album) |album| allocator.free(album);
        if (self.date) |date| allocator.free(date);
        if (self.genre) |genre| allocator.free(genre);
        if (self.comment) |comment| allocator.free(comment);
    }
};

pub fn readWavMetadata(allocator: std.mem.Allocator, file_path: []const u8) !WavMetadata {
    var reader = try io.AudioReader.init(allocator, file_path);
    defer reader.deinit();

    var metadata = WavMetadata{};

    // Skip RIFF header
    try reader.seek(12);

    // Look for LIST chunk containing INFO
    while (try reader.getPos() < try reader.getEndPos()) {
        var chunk_id: [4]u8 = undefined;
        const bytes_read = try reader.readBytes(chunk_id[0..]);
        if (bytes_read < 4) break;

        const chunk_size = try reader.readU32Le();
        const chunk_end = try reader.getPos() + chunk_size;

        if (std.mem.eql(u8, &chunk_id, "LIST")) {
            var list_type: [4]u8 = undefined;
            _ = try reader.readBytes(list_type[0..]);

            if (std.mem.eql(u8, &list_type, "INFO")) {
                try parseInfoChunk(allocator, &reader, &metadata, chunk_end - 4);
            }
        }

        // Skip to next chunk
        try reader.seek(chunk_end);
        if (chunk_size % 2 == 1) {
            try reader.seek(try reader.getPos() + 1); // Padding byte
        }
    }

    return metadata;
}

fn parseInfoChunk(allocator: std.mem.Allocator, reader: *io.AudioReader, metadata: *WavMetadata, chunk_end: u64) !void {
    while (try reader.getPos() < chunk_end) {
        var info_id: [4]u8 = undefined;
        const bytes_read = try reader.readBytes(info_id[0..]);
        if (bytes_read < 4) break;

        const info_size = try reader.readU32Le();
        if (info_size == 0) continue;

        const data = try allocator.alloc(u8, info_size);
        _ = try reader.readBytes(data);

        // Remove null terminator if present
        const trimmed_size = if (data[data.len - 1] == 0) data.len - 1 else data.len;
        const trimmed_data = try allocator.dupe(u8, data[0..trimmed_size]);
        allocator.free(data);

        if (std.mem.eql(u8, &info_id, "INAM")) {
            metadata.title = trimmed_data;
        } else if (std.mem.eql(u8, &info_id, "IART")) {
            metadata.artist = trimmed_data;
        } else if (std.mem.eql(u8, &info_id, "IPRD")) {
            metadata.album = trimmed_data;
        } else if (std.mem.eql(u8, &info_id, "ICRD")) {
            metadata.date = trimmed_data;
        } else if (std.mem.eql(u8, &info_id, "IGNR")) {
            metadata.genre = trimmed_data;
        } else if (std.mem.eql(u8, &info_id, "ICMT")) {
            metadata.comment = trimmed_data;
        } else {
            allocator.free(trimmed_data);
        }

        // Handle padding
        if (info_size % 2 == 1) {
            try reader.seek(try reader.getPos() + 1);
        }
    }
}