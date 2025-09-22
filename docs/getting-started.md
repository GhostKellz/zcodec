# Getting Started with zcodec

This guide will help you get up and running with zcodec, a pure Zig audio codec library.

## Installation

### Adding zcodec to your project

1. Use `zig fetch` to add zcodec to your project:

```bash
zig fetch --save https://github.com/ghostkellz/zcodec/archive/refs/heads/main.tar.gz
```

This will automatically add zcodec to your `build.zig.zon` dependencies with the correct hash.

2. Update your `build.zig` to include the dependency:

```zig
pub fn build(b: *std.Build) void {
    // ... existing code ...

    const zcodec_dep = b.dependency("zcodec", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zcodec", zcodec_dep.module("zcodec"));
}
```

3. Import zcodec in your Zig source files:

```zig
const zcodec = @import("zcodec");
```

## Basic Concepts

### Sample Types

zcodec uses a union type to represent audio samples in different formats:

```zig
pub const Sample = union(enum) {
    i16: i16,    // 16-bit signed integer
    i24: i24,    // 24-bit signed integer
    i32: i32,    // 32-bit signed integer
    f32: f32,    // 32-bit floating point
};
```

### Memory Management

All zcodec functions that allocate memory require an allocator. Always remember to clean up:

```zig
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
defer _ = gpa.deinit();
const allocator = gpa.allocator();

// Use allocator with zcodec functions
const result = try zcodec.readWavFile(allocator, "audio.wav");
defer {
    result.wav_file.deinit();
    var decoder = zcodec.PcmDecoder.init(allocator, &result.wav_file);
    decoder.deinit(result.samples);
    result.metadata.deinit(allocator);
}
```

## Your First Program

Here's a complete example that reads a WAV file and prints its information:

```zig
const std = @import("std");
const zcodec = @import("zcodec");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read a WAV file
    const result = try zcodec.readWavFile(allocator, "input.wav");
    defer {
        result.wav_file.deinit();
        var decoder = zcodec.PcmDecoder.init(allocator, &result.wav_file);
        decoder.deinit(result.samples);
        result.metadata.deinit(allocator);
    }

    // Print file information
    const header = result.wav_file.header;
    std.debug.print("File: input.wav\n");
    std.debug.print("Sample Rate: {} Hz\n", .{header.sample_rate});
    std.debug.print("Channels: {}\n", .{header.num_channels});
    std.debug.print("Bit Depth: {} bits\n", .{header.bits_per_sample});
    std.debug.print("Duration: {:.2} seconds\n", .{result.wav_file.getDurationSeconds()});
    std.debug.print("Total Samples: {}\n", .{result.wav_file.getSampleCount()});

    // Print metadata if available
    if (result.metadata.title) |title| {
        std.debug.print("Title: {s}\n", .{title});
    }
    if (result.metadata.artist) |artist| {
        std.debug.print("Artist: {s}\n", .{artist});
    }
}
```

## Common Patterns

### Reading Audio Files

```zig
// Simple file reading
const result = try zcodec.readWavFile(allocator, "audio.wav");
defer cleanup(result, allocator);

// Access audio data
const samples = result.samples; // [][]Sample - array of channels
const first_channel = samples[0]; // []Sample
const first_sample = first_channel[0]; // Sample
```

### Creating Audio Files

```zig
// Generate a sine wave
const sample_rate = 44100;
const duration = 1.0; // 1 second
const sample_count = @as(usize, @intFromFloat(sample_rate * duration));

const samples = try allocator.alloc(zcodec.Sample, sample_count);
defer allocator.free(samples);

for (samples, 0..) |*sample, i| {
    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_rate));
    const freq = 440.0; // A4 note
    sample.* = zcodec.Sample{ .f32 = 0.5 * @sin(2.0 * std.math.pi * freq * t) };
}

// Create channels (mono in this case)
var channels = [_][]zcodec.Sample{samples};

// Write to file
try zcodec.writeWavFile(allocator, "output.wav", &channels, sample_rate, 32);
```

### Working with Multiple Channels

```zig
// Stereo audio example
const left_channel = try allocator.alloc(zcodec.Sample, sample_count);
const right_channel = try allocator.alloc(zcodec.Sample, sample_count);
defer allocator.free(left_channel);
defer allocator.free(right_channel);

// Fill channels with different frequencies
for (left_channel, 0..) |*sample, i| {
    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_rate));
    sample.* = zcodec.Sample{ .f32 = 0.3 * @sin(2.0 * std.math.pi * 440.0 * t) }; // Left: 440 Hz
}

for (right_channel, 0..) |*sample, i| {
    const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(sample_rate));
    sample.* = zcodec.Sample{ .f32 = 0.3 * @sin(2.0 * std.math.pi * 523.25 * t) }; // Right: 523.25 Hz (C5)
}

var stereo_channels = [_][]zcodec.Sample{ left_channel, right_channel };
try zcodec.writeWavFile(allocator, "stereo.wav", &stereo_channels, sample_rate, 32);
```

## Error Handling

zcodec functions return error unions. Common errors include:

- `OutOfMemory` - Insufficient memory
- `InvalidFormat` - Corrupted or unsupported file format
- `UnsupportedFormat` - File format not yet supported
- `FileNotFound` - Input file doesn't exist
- `AccessDenied` - Permission issues

Always handle errors appropriately:

```zig
const result = zcodec.readWavFile(allocator, "audio.wav") catch |err| switch (err) {
    error.FileNotFound => {
        std.debug.print("Error: File not found\n");
        return;
    },
    error.InvalidFormat => {
        std.debug.print("Error: Invalid or corrupted WAV file\n");
        return;
    },
    else => return err,
};
```

## Next Steps

- Check out the [API Reference](api-reference.md) for detailed function documentation
- Explore the examples in the repository
- Read about supported formats and their limitations
- Learn about advanced features like streaming and seeking (coming soon)