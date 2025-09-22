const std = @import("std");

pub const AudioReader = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Self {
        const file = try std.fs.cwd().openFile(file_path, .{});
        return Self{
            .allocator = allocator,
            .file = file,
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    pub fn readBytes(self: *Self, buffer: []u8) !usize {
        return try self.file.readAll(buffer);
    }

    pub fn readU32Le(self: *Self) !u32 {
        var bytes: [4]u8 = undefined;
        _ = try self.file.readAll(bytes[0..]);
        return std.mem.readInt(u32, &bytes, .little);
    }

    pub fn readU16Le(self: *Self) !u16 {
        var bytes: [2]u8 = undefined;
        _ = try self.file.readAll(bytes[0..]);
        return std.mem.readInt(u16, &bytes, .little);
    }

    pub fn seek(self: *Self, pos: u64) !void {
        try self.file.seekTo(pos);
    }

    pub fn getPos(self: *Self) !u64 {
        return try self.file.getPos();
    }

    pub fn getEndPos(self: *Self) !u64 {
        return try self.file.getEndPos();
    }
};

pub const AudioWriter = struct {
    allocator: std.mem.Allocator,
    file: std.fs.File,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, file_path: []const u8) !Self {
        const file = try std.fs.cwd().createFile(file_path, .{});
        return Self{
            .allocator = allocator,
            .file = file,
        };
    }

    pub fn deinit(self: *Self) void {
        self.file.close();
    }

    pub fn writeBytes(self: *Self, buffer: []const u8) !void {
        try self.file.writeAll(buffer);
    }

    pub fn writeU32Le(self: *Self, value: u32) !void {
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, value, .little);
        try self.file.writeAll(bytes[0..]);
    }

    pub fn writeU16Le(self: *Self, value: u16) !void {
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, value, .little);
        try self.file.writeAll(bytes[0..]);
    }

    pub fn seek(self: *Self, pos: u64) !void {
        try self.file.seekTo(pos);
    }

    pub fn getPos(self: *Self) !u64 {
        return try self.file.getPos();
    }
};