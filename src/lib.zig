const std = @import("std");
const builtin = @import("builtin");
const Chameleon = @import("chameleon").Chameleon;

const fs = std.fs;
const mem = std.mem;

const File = fs.File;
const Allocator = mem.Allocator;

pub fn readFile(allocator: Allocator, filename: []const u8) (File.ReadError || File.GetSeekPosError || File.OpenError || Allocator.Error || fs.SelfExePathError)![]u8 {
    const SEPARATOR = comptime if (builtin.os.tag == .windows) "\\" else "/";

    const file = fs.cwd().openFile(filename, .{}) catch |e| blk: {
        if (e == File.OpenError.FileNotFound) {
            const exeDirPath = try fs.selfExePathAlloc(allocator);
            defer allocator.free(exeDirPath);

            const pathFromExe = try mem.join(allocator, SEPARATOR, &.{
                exeDirPath,
                filename,
            });
            defer allocator.free(pathFromExe);

            break :blk fs.openFileAbsolute(pathFromExe, .{}) catch |e2| return e2;
        }
        return e;
    };
    defer file.close();

    return @errorCast(file.reader().readAllAlloc(allocator, try file.getEndPos()));
}

const TokenKind = enum {
    /// `hey`: `*[]const u8`
    Identifier,
    /// `5159.4654`: `*f64`
    Number,
    /// `"hey, vsauce, michael here"`: `*[]const u8`
    String,
    /// `=`: `null`
    Equal,
    /// `,`: `null`
    Comma,
    /// `{`: `null`
    BraceOpen,
    /// `}`: `null`
    BraceClose,
    /// `[`: `null`
    BracketOpen,
    /// `]`: `null`
    BracketClose,
};

const Token = struct {
    kind: TokenKind,
    data: ?*anyopaque = null,
    // debugging info
    file: ?[]const u8 = null,
    line: u32 = 1,
    column: u32 = 1,

    pub fn format(self: Token, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        const dataAsString: ?*[]const u8 = if (self.data) |p| @ptrCast(@constCast(@alignCast(p))) else null;
        const dataAsF64: ?*f64 = if (self.data) |p| @ptrCast(@constCast(@alignCast(p))) else null;
        if (self.file) |f| {
            const fullFilePath = .{ f, self.line, self.column };
            try switch (self.kind) {
                .Identifier => stream.print("Token{{ kind = .Identifier, .name = {s}, .file = {s}:{d}:{d} }}", .{dataAsString.?.*} ++ fullFilePath),
                .String => stream.print("Token{{ kind = .String, .value = \"{s}\", .file = {s}:{d}:{d} }}", .{dataAsString.?.*} ++ fullFilePath),
                .Number => stream.print("Token{{ kind = .Number, .value = {d}, .file = {s}:{d}:{d} }}", .{dataAsF64.?.*} ++ fullFilePath),
                .Equal => stream.print("Token{{ kind = .Equal, .file = {s}:{d}:{d} }}", fullFilePath),
                .Comma => stream.print("Token{{ kind = .Comma, .file = {s}:{d}:{d} }}", fullFilePath),
                .BraceOpen => stream.print("Token{{ kind = .Brace.Open, .file = {s}:{d}:{d} }}", fullFilePath),
                .BraceClose => stream.print("Token{{ kind = .Brace.Close, .file = {s}:{d}:{d} }}", fullFilePath),
                .BracketOpen => stream.print("Token{{ kind = .Bracket.Open, .file = {s}:{d}:{d} }}", fullFilePath),
                .BracketClose => stream.print("Token{{ kind = .Bracket.Close, .file = {s}:{d}:{d} }}", fullFilePath),
            };
        } else {
            const fullFilePath = .{ self.line, self.column };
            try switch (self.kind) {
                .Identifier => stream.print("Token{{ kind = .Identifier, .name = {s}, .file = {d}:{d} }}", .{dataAsString.?.*} ++ fullFilePath),
                .String => stream.print("Token{{ kind = .String, .value = \"{s}\", .file = {d}:{d} }}", .{dataAsString.?.*} ++ fullFilePath),
                .Number => stream.print("Token{{ kind = .Number, .value = {d}, .file = {d}:{d} }}", .{dataAsF64.?.*} ++ fullFilePath),
                .Equal => stream.print("Token{{ kind = .Equal, .file = {d}:{d} }}", fullFilePath),
                .Comma => stream.print("Token{{ kind = .Comma, .file = {d}:{d} }}", fullFilePath),
                .BraceOpen => stream.print("Token{{ kind = .Brace.Open, .file = {d}:{d} }}", fullFilePath),
                .BraceClose => stream.print("Token{{ kind = .Brace.Close, .file = {d}:{d} }}", fullFilePath),
                .BracketOpen => stream.print("Token{{ kind = .Bracket.Open, .file = {d}:{d} }}", fullFilePath),
                .BracketClose => stream.print("Token{{ kind = .Bracket.Close, .file = {d}:{d} }}", fullFilePath),
            };
        }
    }

    pub fn deinit(self: *Token, allocator: Allocator) void {
        const dataAsString: ?*[]const u8 = if (self.data) |p| @ptrCast(@constCast(@alignCast(p))) else null;
        const dataAsF64: ?*f64 = if (self.data) |p| @ptrCast(@constCast(@alignCast(p))) else null;
        switch (self.kind) {
            .Identifier, .String => {
                allocator.free(dataAsString.?.*);
                allocator.destroy(dataAsString.?);
            },
            .Number => allocator.destroy(dataAsF64.?),
            else => {},
        }
        self.* = undefined;
    }
};

pub const Error = error{
    UnknownCharacter,
    EmptyToken,
    UnclosedString,
    InvalidSpecialCharacter,
    WrongNumberFormat,
    OutOfMemory,
    IncompleteComment,
};
pub const DebugInfo = struct {
    file: ?[]const u8 = null,
    line: u32 = 1,
    column: u32 = 1,

    pub fn format(self: DebugInfo, comptime _: []const u8, _: std.fmt.FormatOptions, stream: anytype) !void {
        if (self.file) |f|
            try stream.print("{s}:{d}:{d}", .{ f, self.line, self.column })
        else
            try stream.print("{d}:{d}", .{ self.line, self.column });
    }
};

fn toToken(allocator: Allocator, line: u32, column: u32, file: ?[]const u8, str: []const u8) Error!Token {
    if (str.len == 0) return Error.EmptyToken;
    if (str[0] >= '0' and str[0] <= '9') {
        const n = std.fmt.parseFloat(f64, str) catch return Error.WrongNumberFormat;
        const nPtr = try allocator.create(f64);
        errdefer allocator.destroy(nPtr);
        nPtr.* = n;
        const v = Token{
            .kind = .Number,
            .data = @ptrCast(@alignCast(nPtr)),
            .file = file,
            .line = line,
            .column = @intCast(column - str.len),
        };
        allocator.free(str);
        return v;
    } else {
        const sPtr = try allocator.create([]const u8);
        errdefer allocator.destroy(sPtr);
        sPtr.* = str;
        return .{
            .kind = .Identifier,
            .data = @ptrCast(@alignCast(sPtr)),
            .file = file,
            .line = line,
            .column = @intCast(column - str.len),
        };
    }
}

pub fn tokenize(allocator: Allocator, src: []const u8, file: ?[]const u8, info_out: ?*DebugInfo) Error![]Token {
    var tokenList = std.ArrayList(Token).init(allocator);
    defer {
        for (tokenList.items) |*token| token.deinit(allocator);
        tokenList.deinit();
    }
    var currentToken = std.ArrayList(u8).init(allocator);
    defer currentToken.deinit();

    var line: u32 = 1;
    var column: u32 = 1;

    errdefer {
        if (info_out) |*info| {
            info.*.file = file;
            info.*.line = line;
            info.*.column = column;
        }
    }

    var commenting: bool = false;
    var multilineComment: bool = false;
    var stringing: bool = false;
    var multilineString: bool = false;
    var startLine: u32 = 0;
    var startColumn: u32 = 0;
    var didLineFeed: bool = false;
    var i: u32 = 0;
    while (i < src.len) : ({
        i += 1;
        column += 1;
    }) {
        const c = src[i];
        const nc: u8 = if (i + 1 < src.len) src[i + 1] else 255;

        //std.debug.print("Char at [{d}], {?s}:{d}:{d}\n", .{ i, file, line, column });

        if (commenting) {
            if (c == nc) {
                if (c == '[') {
                    multilineComment = true;
                } else if (c == ']') {
                    multilineComment = false;
                    commenting = false;
                }
                column += 1;
                i += 1;
            }
            if (c == '\n' or c == '\r') {
                column = 0;
                if (!didLineFeed) {
                    line += 1;
                    didLineFeed = true;
                }
                if (!multilineComment)
                    commenting = false;
            }
            continue;
        }
        if (stringing) {
            if (c == '\n' or c == '\r') return Error.UnclosedString;
            if (c == '"') {
                stringing = false;
                const sPtr = try allocator.create([]const u8);
                errdefer allocator.destroy(sPtr);
                sPtr.* = try currentToken.toOwnedSlice();
                try tokenList.append(.{
                    .kind = .String,
                    .data = @ptrCast(@alignCast(sPtr)),
                    .file = file,
                    .line = startLine,
                    .column = startColumn,
                });
                continue;
            }
            try switch (c) {
                '\\' => {
                    if (nc == 't')
                        try currentToken.append('\t')
                    else if (nc == 'r')
                        try currentToken.append('\r')
                    else if (nc == 'n')
                        try currentToken.append('\n')
                    else if (nc == '0')
                        try currentToken.append(0)
                    else if (nc == '\\')
                        try currentToken.append('\\')
                    else if (nc == '"')
                        try currentToken.append('"')
                    else
                        return Error.InvalidSpecialCharacter;
                    column += 1;
                    i += 1;
                },
                else => currentToken.append(c),
            };
            continue;
        }
        if (multilineString) {
            if (c == nc and c == ']') {
                multilineString = false;
                const sPtr = try allocator.create([]const u8);
                errdefer allocator.destroy(sPtr);
                sPtr.* = try currentToken.toOwnedSlice();
                try tokenList.append(.{
                    .kind = .String,
                    .data = @ptrCast(@alignCast(sPtr)),
                    .file = file,
                    .line = startLine,
                    .column = startColumn,
                });
                column += 1;
                i += 1;
                continue;
            }
            if (c == '\n' or c == '\r') {
                column = 0;
                if (!didLineFeed) {
                    line += 1;
                    didLineFeed = true;
                }
            } else {
                didLineFeed = false;
            }
            try switch (c) {
                '\\' => {
                    if (nc == ']')
                        try currentToken.append(']')
                    else if (nc == 't')
                        try currentToken.append('\t')
                    else if (nc == '0')
                        try currentToken.append(0)
                    else if (nc == '\\')
                        try currentToken.append('\\')
                    else
                        return Error.InvalidSpecialCharacter;
                    column += 1;
                    i += 1;
                },
                else => currentToken.append(c),
            };
            continue;
        }

        if (!(c == '\n' or c == '\r')) didLineFeed = false;
        switch (c) {
            '"', ',', '{', '}', '[', ']', ' ', '-', '=' => {
                if (currentToken.items.len > 0) {
                    try tokenList.append(try toToken(allocator, line, column, file, try currentToken.toOwnedSlice()));
                }
            },
            else => {},
        }
        switch (c) {
            '\n', '\r' => {
                if (currentToken.items.len > 0) {
                    try tokenList.append(try toToken(allocator, line, column, file, try currentToken.toOwnedSlice()));
                }
                column = 0;
                if (!didLineFeed) {
                    line += 1;
                    didLineFeed = true;
                }
            },
            ' ' => {},
            '"' => {
                stringing = true;
                startLine = line;
                startColumn = column;
            },
            ',' => try tokenList.append(.{
                .kind = .Comma,
                .file = file,
                .line = line,
                .column = column,
            }),
            '{' => try tokenList.append(.{
                .kind = .BraceOpen,
                .file = file,
                .line = line,
                .column = column,
            }),
            '}' => try tokenList.append(.{
                .kind = .BraceClose,
                .file = file,
                .line = line,
                .column = column,
            }),
            '[' => {
                if (c == nc) {
                    multilineString = true;
                    startLine = line;
                    startColumn = column;
                    column += 1;
                    i += 1;
                    continue;
                }
                try tokenList.append(.{
                    .kind = .BracketOpen,
                    .file = file,
                    .line = line,
                    .column = column,
                });
            },
            ']' => try tokenList.append(.{
                .kind = .BracketClose,
                .file = file,
                .line = line,
                .column = column,
            }),
            '-' => {
                if (nc != '-') return Error.IncompleteComment;
                commenting = true;
                multilineComment = false;
                column += 1;
                i += 1;
            },
            '=' => try tokenList.append(.{
                .kind = .Equal,
                .file = file,
                .line = line,
                .column = column,
            }),
            else => {
                const ptr = try currentToken.addOne();
                ptr.* = c;
            },
        }
    }

    if (multilineString) return Error.UnclosedString;

    if (currentToken.items.len > 0) {
        try tokenList.append(try toToken(allocator, line, column, file, try currentToken.toOwnedSlice()));
    }

    return tokenList.toOwnedSlice();
}
pub fn freeTokens(allocator: Allocator, tokens: []Token) void {
    for (tokens) |*token| token.deinit(allocator);
    allocator.free(tokens);
}

pub const Value = union(enum) {
    String: []const u8,
    Number: f64,
    Table: TableValue,
    Nil,
    None,

    pub fn deinit(self: *Value, allocator: Allocator) void {
        switch (self.*) {
            .String => |d| allocator.free(d),
            .Table => |d| d.deinit(),
            else => {},
        }
        self.* = undefined;
    }

    pub fn eql(self: Value, lhs: Value) bool {
        const atag = std.meta.activeTag;
        if (atag(self) != atag(lhs)) return false;
        return switch (self) {
            .String => |d| mem.eql(u8, d, lhs.String),
            .Number => |d| d == lhs.Number,
            .Table => |_| false,
            .Nil, .None => true,
        };
    }
};
pub const TablePair = struct {
    name: Value,
    value: Value,

    pub fn deinit(self: *TablePair, allocator: Allocator) void {
        self.name.deinit(allocator);
        self.value.deinit(allocator);
    }
};
pub const TableValue = struct {
    allocator: Allocator,
    pairs: ?[]TablePair = null,

    pub fn init(allocator: Allocator) TableValue {
        return .{
            .allocator = allocator,
            .pairs = null,
        };
    }
    pub fn deinit(self: *TableValue) void {
        const allocator = self.allocator;
        if (self.pairs) |pairs| {
            for (pairs) |p| p.deinit(allocator);
            allocator.free(pairs);
        }
        self.* = undefined;
    }

    pub fn getName(self: *TableValue, n: []const u8) Value {
        return self.getValIndex(.{ .String = n });
    }
    pub fn getAt(self: *TableValue, i: u32) Value {
        return self.getValIndex(.{ .Number = @floatFromInt(i) });
    }
    pub fn getValIndex(self: *TableValue, v: Value) Value {
        if (self.pairs) |pairs| {
            for (pairs) |p| {
                if (p.name.eql(v)) {
                    return p.value;
                }
            }
        }
        return .None;
    }
};

pub fn parseTokens(allocator: Allocator, tokens: []Token) Error!TableValue {
    _ = allocator; // autofix
    _ = tokens; // autofix

}
