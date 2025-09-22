const std = @import("std");
const io = @import("io.zig");

pub const WavError = error{
    InvalidFormat,
    UnsupportedFormat,
    InvalidHeader,
    OutOfMemory,
} || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.File.WriteError || std.fs.File.SeekError;

pub const AudioFormat = enum(u16) {
    pcm = 1,
    ieee_float = 3,
    alaw = 6,
    mulaw = 7,
    extensible = 0xFFFE,
};

pub const WavHeader = struct {
    chunk_id: [4]u8, // "RIFF"
    chunk_size: u32,
    format: [4]u8, // "WAVE"
    subchunk1_id: [4]u8, // "fmt "
    subchunk1_size: u32,
    audio_format: AudioFormat,
    num_channels: u16,
    sample_rate: u32,
    byte_rate: u32,
    block_align: u16,
    bits_per_sample: u16,
    subchunk2_id: [4]u8, // "data"
    subchunk2_size: u32,

    pub fn init(sample_rate: u32, num_channels: u16, bits_per_sample: u16) WavHeader {
        const byte_rate = sample_rate * num_channels * bits_per_sample / 8;
        const block_align = num_channels * bits_per_sample / 8;

        return WavHeader{
            .chunk_id = [_]u8{ 'R', 'I', 'F', 'F' },
            .chunk_size = 36, // Will be updated when data is written
            .format = [_]u8{ 'W', 'A', 'V', 'E' },
            .subchunk1_id = [_]u8{ 'f', 'm', 't', ' ' },
            .subchunk1_size = 16,
            .audio_format = AudioFormat.pcm,
            .num_channels = num_channels,
            .sample_rate = sample_rate,
            .byte_rate = byte_rate,
            .block_align = @intCast(block_align),
            .bits_per_sample = bits_per_sample,
            .subchunk2_id = [_]u8{ 'd', 'a', 't', 'a' },
            .subchunk2_size = 0, // Will be updated when data is written
        };
    }
};

pub const WavFile = struct {
    allocator: std.mem.Allocator,
    header: WavHeader,
    data: []u8,

    const Self = @This();

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.data);
    }

    pub fn readFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Self {
        var reader = try io.AudioReader.init(allocator, file_path);
        defer reader.deinit();

        var header: WavHeader = undefined;

        // Read RIFF header
        _ = try reader.readBytes(header.chunk_id[0..]);
        if (!std.mem.eql(u8, &header.chunk_id, "RIFF")) {
            return WavError.InvalidFormat;
        }

        header.chunk_size = try reader.readU32Le();

        _ = try reader.readBytes(header.format[0..]);
        if (!std.mem.eql(u8, &header.format, "WAVE")) {
            return WavError.InvalidFormat;
        }

        // Read fmt chunk
        _ = try reader.readBytes(header.subchunk1_id[0..]);
        if (!std.mem.eql(u8, &header.subchunk1_id, "fmt ")) {
            return WavError.InvalidFormat;
        }

        header.subchunk1_size = try reader.readU32Le();
        const audio_format_raw = try reader.readU16Le();
        header.audio_format = @enumFromInt(audio_format_raw);
        header.num_channels = try reader.readU16Le();
        header.sample_rate = try reader.readU32Le();
        header.byte_rate = try reader.readU32Le();
        header.block_align = try reader.readU16Le();
        header.bits_per_sample = try reader.readU16Le();

        // Skip any extra format bytes
        if (header.subchunk1_size > 16) {
            try reader.seek(try reader.getPos() + header.subchunk1_size - 16);
        }

        // Find data chunk
        while (true) {
            _ = try reader.readBytes(header.subchunk2_id[0..]);

            if (std.mem.eql(u8, &header.subchunk2_id, "data")) {
                break;
            }

            // Skip this chunk
            const chunk_size = try reader.readU32Le();
            try reader.seek(try reader.getPos() + chunk_size);

            // Check if we've reached the end
            if (try reader.getPos() >= try reader.getEndPos()) {
                return WavError.InvalidFormat;
            }
        }

        header.subchunk2_size = try reader.readU32Le();

        // Read audio data
        const data = try allocator.alloc(u8, header.subchunk2_size);
        _ = try reader.readBytes(data);

        return Self{
            .allocator = allocator,
            .header = header,
            .data = data,
        };
    }

    pub fn writeToFile(self: *Self, file_path: []const u8) !void {
        var writer = try io.AudioWriter.init(self.allocator, file_path);
        defer writer.deinit();

        // Update header sizes
        self.header.subchunk2_size = @intCast(self.data.len);
        self.header.chunk_size = 36 + self.header.subchunk2_size;

        // Write RIFF header
        try writer.writeBytes(&self.header.chunk_id);
        try writer.writeU32Le(self.header.chunk_size);
        try writer.writeBytes(&self.header.format);

        // Write fmt chunk
        try writer.writeBytes(&self.header.subchunk1_id);
        try writer.writeU32Le(self.header.subchunk1_size);
        try writer.writeU16Le(@intFromEnum(self.header.audio_format));
        try writer.writeU16Le(self.header.num_channels);
        try writer.writeU32Le(self.header.sample_rate);
        try writer.writeU32Le(self.header.byte_rate);
        try writer.writeU16Le(self.header.block_align);
        try writer.writeU16Le(self.header.bits_per_sample);

        // Write data chunk
        try writer.writeBytes(&self.header.subchunk2_id);
        try writer.writeU32Le(self.header.subchunk2_size);
        try writer.writeBytes(self.data);
    }

    pub fn getSampleCount(self: *const Self) u32 {
        const bytes_per_sample = self.header.bits_per_sample / 8;
        return self.header.subchunk2_size / (self.header.num_channels * bytes_per_sample);
    }

    pub fn getDurationSeconds(self: *const Self) f64 {
        return @as(f64, @floatFromInt(self.getSampleCount())) / @as(f64, @floatFromInt(self.header.sample_rate));
    }
};