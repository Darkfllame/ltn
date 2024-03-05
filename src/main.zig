const std = @import("std");
const lib = @import("lib.zig");
const Chameleon = @import("chameleon").Chameleon;

const fs = std.fs;
const mem = std.mem;
const heap = std.heap;
const readFile = lib.readFile;

const File = fs.File;
const Allocator = mem.Allocator;

const gpaConfig = .{};
const GPA = heap.GeneralPurposeAllocator(gpaConfig);

var gpa: GPA = undefined;

pub fn getGPA() GPA {
    return gpa;
}

pub fn main() !void {
    comptime var cham = Chameleon.init(.Auto);

    gpa = GPA{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const filename = if (args.len > 1) args[1] else "test.ltn";

    std.debug.print("Reading file\n", .{});
    const content = try readFile(allocator, filename);
    defer allocator.free(content);

    var debugInfo: lib.DebugInfo = undefined;
    std.debug.print("Tokenizing file\n", .{});
    const tokens = lib.tokenize(allocator, content, filename, &debugInfo) catch |e| {
        std.debug.print(cham.red().fmt("[ERROR | {s}] Error at {any}\n"), .{ @errorName(e), debugInfo });
        return;
    };
    defer lib.freeTokens(allocator, tokens);

    for (tokens, 0..) |t, i| {
        std.debug.print(cham.green().fmt("[{d}] = {any}\n"), .{ i, t });
    }

    // const table = lib.parseFile(allocator, filename);
    // defer table.deinit();
}
