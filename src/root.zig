//! zcodec: Pure Zig audio codec library
//!
//! This library provides functionality for reading, writing, and processing audio files
//! with a focus on WAV format and PCM encoding/decoding.

const std = @import("std");

// Public API exports
pub const io = @import("io.zig");
pub const wav = @import("wav.zig");
pub const pcm = @import("pcm.zig");
pub const metadata = @import("metadata.zig");

// Re-export commonly used types
pub const WavFile = wav.WavFile;
pub const WavHeader = wav.WavHeader;
pub const AudioFormat = wav.AudioFormat;
pub const Sample = pcm.Sample;
pub const PcmDecoder = pcm.PcmDecoder;
pub const PcmEncoder = pcm.PcmEncoder;
pub const WavMetadata = metadata.WavMetadata;
pub const AudioReader = io.AudioReader;
pub const AudioWriter = io.AudioWriter;

// Convenience functions for common operations

/// Read a WAV file and decode its PCM samples
pub fn readWavFile(allocator: std.mem.Allocator, file_path: []const u8) !struct {
    wav_file: WavFile,
    samples: [][]Sample,
    metadata: WavMetadata,
} {
    var wav_file = try WavFile.readFromFile(allocator, file_path);
    errdefer wav_file.deinit();

    var decoder = PcmDecoder.init(allocator, &wav_file);
    const samples = try decoder.decodeSamples();
    errdefer decoder.deinit(samples);

    const file_metadata = metadata.readWavMetadata(allocator, file_path) catch WavMetadata{};

    return .{
        .wav_file = wav_file,
        .samples = samples,
        .metadata = file_metadata,
    };
}

/// Create and write a WAV file from PCM samples
pub fn writeWavFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    samples: [][]Sample,
    sample_rate: u32,
    bits_per_sample: u16,
) !void {
    var encoder = PcmEncoder.init(allocator);
    var wav_file = try encoder.encodeToWav(samples, sample_rate, bits_per_sample);
    defer wav_file.deinit();

    try wav_file.writeToFile(file_path);
}

test "basic wav file creation" {
    const allocator = std.testing.allocator;

    // Create a simple mono sine wave
    const sample_rate = 44100;
    const duration_ms = 100;
    const sample_count = sample_rate * duration_ms / 1000;

    const samples = try allocator.alloc(Sample, sample_count);
    defer allocator.free(samples);

    for (samples, 0..) |*sample, i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_rate));
        const freq = 440.0; // A4
        const amplitude = 0.5;
        sample.* = Sample{ .f32 = amplitude * @sin(2.0 * std.math.pi * freq * t) };
    }

    var channels = [_][]Sample{samples};

    var encoder = PcmEncoder.init(allocator);
    var wav_file = try encoder.encodeToWav(&channels, sample_rate, 32);
    defer wav_file.deinit();

    try std.testing.expect(wav_file.header.sample_rate == sample_rate);
    try std.testing.expect(wav_file.header.num_channels == 1);
    try std.testing.expect(wav_file.header.bits_per_sample == 32);
}
