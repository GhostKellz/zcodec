const std = @import("std");
const wav = @import("wav.zig");

pub const PcmError = error{
    UnsupportedBitDepth,
    InvalidSampleData,
    OutOfMemory,
};

pub const Sample = union(enum) {
    i16: i16,
    i24: i24,
    i32: i32,
    f32: f32,
};

pub const PcmDecoder = struct {
    allocator: std.mem.Allocator,
    wav_file: *wav.WavFile,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, wav_file: *wav.WavFile) Self {
        return Self{
            .allocator = allocator,
            .wav_file = wav_file,
        };
    }

    pub fn decodeSamples(self: *Self) ![][]Sample {
        const num_channels = self.wav_file.header.num_channels;
        const sample_count = self.wav_file.getSampleCount();
        const bits_per_sample = self.wav_file.header.bits_per_sample;

        // Allocate channels
        const channels = try self.allocator.alloc([]Sample, num_channels);
        for (channels) |*channel| {
            channel.* = try self.allocator.alloc(Sample, sample_count);
        }

        const bytes_per_sample = bits_per_sample / 8;
        var data_pos: usize = 0;

        for (0..sample_count) |sample_idx| {
            for (0..num_channels) |channel_idx| {
                const sample = try self.decodeSingleSample(data_pos, bits_per_sample);
                channels[channel_idx][sample_idx] = sample;
                data_pos += bytes_per_sample;
            }
        }

        return channels;
    }

    fn decodeSingleSample(self: *Self, offset: usize, bits_per_sample: u16) !Sample {
        const data = self.wav_file.data;

        switch (bits_per_sample) {
            16 => {
                if (offset + 2 > data.len) return PcmError.InvalidSampleData;
                const raw = std.mem.readInt(i16, data[offset..offset + 2], .little);
                return Sample{ .i16 = raw };
            },
            24 => {
                if (offset + 3 > data.len) return PcmError.InvalidSampleData;
                var bytes: [4]u8 = [_]u8{ data[offset], data[offset + 1], data[offset + 2], 0 };
                if (bytes[2] & 0x80 != 0) bytes[3] = 0xFF; // Sign extend
                const raw = std.mem.readInt(i32, &bytes, .little);
                return Sample{ .i24 = @intCast(raw >> 8) };
            },
            32 => {
                if (offset + 4 > data.len) return PcmError.InvalidSampleData;
                if (self.wav_file.header.audio_format == wav.AudioFormat.ieee_float) {
                    const raw = std.mem.readInt(u32, data[offset..offset + 4], .little);
                    return Sample{ .f32 = @bitCast(raw) };
                } else {
                    const raw = std.mem.readInt(i32, data[offset..offset + 4], .little);
                    return Sample{ .i32 = raw };
                }
            },
            else => return PcmError.UnsupportedBitDepth,
        }
    }

    pub fn deinit(self: *Self, channels: [][]Sample) void {
        for (channels) |channel| {
            self.allocator.free(channel);
        }
        self.allocator.free(channels);
    }
};

pub const PcmEncoder = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn encodeToWav(
        self: *Self,
        channels: [][]Sample,
        sample_rate: u32,
        bits_per_sample: u16,
    ) !wav.WavFile {
        if (channels.len == 0) return PcmError.InvalidSampleData;

        const num_channels = @as(u16, @intCast(channels.len));
        const sample_count = channels[0].len;
        const bytes_per_sample = bits_per_sample / 8;
        const data_size = sample_count * num_channels * bytes_per_sample;

        // Validate all channels have same length
        for (channels) |channel| {
            if (channel.len != sample_count) return PcmError.InvalidSampleData;
        }

        const data = try self.allocator.alloc(u8, data_size);
        var data_pos: usize = 0;

        for (0..sample_count) |sample_idx| {
            for (channels) |channel| {
                try self.encodeSingleSample(channel[sample_idx], data[data_pos..], bits_per_sample);
                data_pos += bytes_per_sample;
            }
        }

        const header = wav.WavHeader.init(sample_rate, num_channels, bits_per_sample);

        return wav.WavFile{
            .allocator = self.allocator,
            .header = header,
            .data = data,
        };
    }

    fn encodeSingleSample(self: *Self, sample: Sample, buffer: []u8, bits_per_sample: u16) !void {
        _ = self;
        switch (bits_per_sample) {
            16 => {
                const value = switch (sample) {
                    .i16 => |v| v,
                    .i24 => |v| @as(i16, @intCast(v >> 8)),
                    .i32 => |v| @as(i16, @intCast(v >> 16)),
                    .f32 => |v| @as(i16, @intFromFloat(v * 32767.0)),
                };
                std.mem.writeInt(i16, buffer[0..2], value, .little);
            },
            24 => {
                const value = switch (sample) {
                    .i16 => |v| @as(i32, v) << 8,
                    .i24 => |v| @as(i32, v),
                    .i32 => |v| v >> 8,
                    .f32 => |v| @as(i32, @intFromFloat(v * 8388607.0)),
                };
                buffer[0] = @intCast(value & 0xFF);
                buffer[1] = @intCast((value >> 8) & 0xFF);
                buffer[2] = @intCast((value >> 16) & 0xFF);
            },
            32 => {
                const value: u32 = switch (sample) {
                    .i16 => |v| @bitCast(@as(i32, v) << 16),
                    .i24 => |v| @bitCast(@as(i32, v) << 8),
                    .i32 => |v| @bitCast(v),
                    .f32 => |v| @bitCast(v),
                };
                std.mem.writeInt(u32, buffer[0..4], value, .little);
            },
            else => return PcmError.UnsupportedBitDepth,
        }
    }
};