# API Reference

Complete reference for the zcodec library API.

## Core Types

### Sample

Union type representing audio samples in different formats.

```zig
pub const Sample = union(enum) {
    i16: i16,    // 16-bit signed integer
    i24: i24,    // 24-bit signed integer
    i32: i32,    // 32-bit signed integer
    f32: f32,    // 32-bit IEEE floating point
};
```

**Usage:**
```zig
const sample_16 = Sample{ .i16 = 32767 };
const sample_float = Sample{ .f32 = 0.5 };
```

### WavFile

Represents a WAV audio file with header and audio data.

```zig
pub const WavFile = struct {
    allocator: std.mem.Allocator,
    header: WavHeader,
    data: []u8,

    pub fn deinit(self: *Self) void
    pub fn readFromFile(allocator: std.mem.Allocator, file_path: []const u8) !Self
    pub fn writeToFile(self: *Self, file_path: []const u8) !void
    pub fn getSampleCount(self: *const Self) u32
    pub fn getDurationSeconds(self: *const Self) f64
};
```

**Methods:**

#### `deinit()`
Frees allocated memory. Must be called to prevent memory leaks.

#### `readFromFile(allocator, file_path)`
Reads a WAV file from disk.
- **Returns:** `WavFile` struct
- **Errors:** `OutOfMemory`, `InvalidFormat`, `FileNotFound`

#### `writeToFile(file_path)`
Writes the WAV file to disk.
- **Errors:** `AccessDenied`, `OutOfMemory`

#### `getSampleCount()`
Returns the total number of audio samples per channel.

#### `getDurationSeconds()`
Returns the audio duration in seconds as a floating-point value.

### WavHeader

Contains WAV file format information.

```zig
pub const WavHeader = struct {
    chunk_id: [4]u8,        // "RIFF"
    chunk_size: u32,        // File size - 8 bytes
    format: [4]u8,          // "WAVE"
    subchunk1_id: [4]u8,    // "fmt "
    subchunk1_size: u32,    // Format chunk size
    audio_format: AudioFormat,
    num_channels: u16,      // 1 = mono, 2 = stereo, etc.
    sample_rate: u32,       // Samples per second
    byte_rate: u32,         // Bytes per second
    block_align: u16,       // Bytes per sample (all channels)
    bits_per_sample: u16,   // Bits per sample
    subchunk2_id: [4]u8,    // "data"
    subchunk2_size: u32,    // Audio data size in bytes

    pub fn init(sample_rate: u32, num_channels: u16, bits_per_sample: u16) WavHeader
};
```

### AudioFormat

Enum representing supported audio encoding formats.

```zig
pub const AudioFormat = enum(u16) {
    pcm = 1,
    ieee_float = 3,
    alaw = 6,
    mulaw = 7,
    extensible = 0xFFFE,
};
```

### WavMetadata

Container for WAV file metadata from INFO chunks.

```zig
pub const WavMetadata = struct {
    title: ?[]u8,
    artist: ?[]u8,
    album: ?[]u8,
    date: ?[]u8,
    genre: ?[]u8,
    comment: ?[]u8,

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void
};
```

**Methods:**

#### `deinit(allocator)`
Frees all allocated metadata strings.

## Decoder/Encoder Types

### PcmDecoder

Decodes PCM audio data to sample arrays.

```zig
pub const PcmDecoder = struct {
    pub fn init(allocator: std.mem.Allocator, wav_file: *WavFile) Self
    pub fn decodeSamples(self: *Self) ![][]Sample
    pub fn deinit(self: *Self, channels: [][]Sample) void
};
```

**Methods:**

#### `init(allocator, wav_file)`
Creates a new PCM decoder for the given WAV file.

#### `decodeSamples()`
Decodes audio data into channel arrays.
- **Returns:** `[][]Sample` - Array of channels, each containing samples
- **Errors:** `UnsupportedBitDepth`, `InvalidSampleData`, `OutOfMemory`

#### `deinit(channels)`
Frees memory allocated for decoded samples.

### PcmEncoder

Encodes sample arrays to PCM audio data.

```zig
pub const PcmEncoder = struct {
    pub fn init(allocator: std.mem.Allocator) Self
    pub fn encodeToWav(self: *Self, channels: [][]Sample, sample_rate: u32, bits_per_sample: u16) !WavFile
};
```

**Methods:**

#### `init(allocator)`
Creates a new PCM encoder.

#### `encodeToWav(channels, sample_rate, bits_per_sample)`
Encodes sample arrays into a WAV file structure.
- **Parameters:**
  - `channels`: Array of sample arrays (one per channel)
  - `sample_rate`: Audio sample rate in Hz
  - `bits_per_sample`: Bit depth (16, 24, or 32)
- **Returns:** `WavFile` struct ready for writing
- **Errors:** `InvalidSampleData`, `UnsupportedBitDepth`, `OutOfMemory`

## I/O Types

### AudioReader

Low-level file reader with audio-specific methods.

```zig
pub const AudioReader = struct {
    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Self
    pub fn deinit(self: *Self) void
    pub fn readBytes(self: *Self, buffer: []u8) !usize
    pub fn readU32Le(self: *Self) !u32
    pub fn readU16Le(self: *Self) !u16
    pub fn seek(self: *Self, pos: u64) !void
    pub fn getPos(self: *Self) !u64
    pub fn getEndPos(self: *Self) !u64
};
```

### AudioWriter

Low-level file writer with audio-specific methods.

```zig
pub const AudioWriter = struct {
    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Self
    pub fn deinit(self: *Self) void
    pub fn writeBytes(self: *Self, buffer: []const u8) !void
    pub fn writeU32Le(self: *Self, value: u32) !void
    pub fn writeU16Le(self: *Self, value: u16) !void
    pub fn seek(self: *Self, pos: u64) !void
    pub fn getPos(self: *Self) !u64
};
```

## High-Level Functions

### readWavFile()

Convenience function that reads and decodes a WAV file in one call.

```zig
pub fn readWavFile(allocator: std.mem.Allocator, file_path: []const u8) !struct {
    wav_file: WavFile,
    samples: [][]Sample,
    metadata: WavMetadata,
}
```

**Parameters:**
- `allocator`: Memory allocator
- `file_path`: Path to WAV file

**Returns:**
Anonymous struct containing:
- `wav_file`: The loaded WAV file
- `samples`: Decoded sample data (array of channels)
- `metadata`: File metadata

**Example:**
```zig
const result = try zcodec.readWavFile(allocator, "audio.wav");
defer {
    result.wav_file.deinit();
    var decoder = zcodec.PcmDecoder.init(allocator, &result.wav_file);
    decoder.deinit(result.samples);
    result.metadata.deinit(allocator);
}
```

### writeWavFile()

Convenience function that encodes and writes a WAV file in one call.

```zig
pub fn writeWavFile(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    samples: [][]Sample,
    sample_rate: u32,
    bits_per_sample: u16,
) !void
```

**Parameters:**
- `allocator`: Memory allocator
- `file_path`: Output file path
- `samples`: Array of channel sample arrays
- `sample_rate`: Sample rate in Hz
- `bits_per_sample`: Bit depth (16, 24, or 32)

**Example:**
```zig
var channels = [_][]Sample{ left_samples, right_samples };
try zcodec.writeWavFile(allocator, "stereo.wav", &channels, 44100, 24);
```

## Metadata Functions

### readWavMetadata()

Reads metadata from WAV INFO chunks.

```zig
pub fn readWavMetadata(allocator: std.mem.Allocator, file_path: []const u8) !WavMetadata
```

**Parameters:**
- `allocator`: Memory allocator
- `file_path`: Path to WAV file

**Returns:** `WavMetadata` struct with available metadata fields

**Example:**
```zig
const metadata = try zcodec.metadata.readWavMetadata(allocator, "audio.wav");
defer metadata.deinit(allocator);

if (metadata.title) |title| {
    std.debug.print("Title: {s}\n", .{title});
}
```

## Error Types

Common error types you may encounter:

### WavError
```zig
pub const WavError = error{
    InvalidFormat,      // File is not a valid WAV file
    UnsupportedFormat,  // WAV format not supported
    InvalidHeader,      // Corrupted header
    OutOfMemory,        // Memory allocation failed
} || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.File.WriteError || std.fs.File.SeekError;
```

### PcmError
```zig
pub const PcmError = error{
    UnsupportedBitDepth,  // Bit depth not supported (not 16/24/32)
    InvalidSampleData,    // Corrupted sample data
    OutOfMemory,          // Memory allocation failed
};
```

### MetadataError
```zig
pub const MetadataError = error{
    InvalidFormat,  // Invalid metadata format
    OutOfMemory,    // Memory allocation failed
} || std.fs.File.OpenError || std.fs.File.ReadError || std.fs.File.SeekError;
```

## Constants and Limits

- **Supported bit depths:** 16, 24, 32 bits
- **Supported audio formats:** PCM, IEEE float
- **Maximum channels:** Limited by available memory
- **Maximum sample rate:** 4,294,967,295 Hz (u32 limit)
- **Maximum file size:** Limited by available memory and filesystem