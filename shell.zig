const std = @import("std");
const os = std.os;
const io = std.io;
const list = std.ArrayList;
const split = std.mem.splitScalar;

//const alloc = std.heap.page_allocator;

const VMIN = 5;
const VTIME = 6;
const STDIN_FD = 0;
const NULLENV = [_:null]?[*:0]u8{null};

// colors and styles
const RED = "\x1B[38;2;224;107;116m";
const GREEN = "\x1B[38;2;152;195;121m";
const BOLD = "\x1B[1m";
const DEFAULT = "\x1B[0m";

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var alloc = gpa.allocator();
var hostnameBuffer: [os.HOST_NAME_MAX]u8 = undefined;
var cwdBuffer: [os.PATH_MAX]u8 = undefined;

fn setRaw(terminal_fd: u8) !void {
    var rawTerm = try os.tcgetattr(terminal_fd);
    rawTerm.iflag &= ~(@as(u16, os.linux.BRKINT | os.linux.ICRNL | os.linux.INPCK | os.linux.ISTRIP | os.linux.IXON));
    rawTerm.oflag &= ~(@as(u8, os.linux.OPOST));
    rawTerm.cflag |= (os.linux.CS8);
    rawTerm.lflag &= ~(@as(u16, os.linux.ECHO | os.linux.ICANON | os.linux.IEXTEN | os.linux.ISIG));
    rawTerm.cc[VMIN] = 0;
    rawTerm.cc[VTIME] = 1;
    try os.tcsetattr(STDIN_FD, os.TCSA.FLUSH, rawTerm);
}

fn getch(terminal_fd: u8) !u8 {
    const currentTermAttr = try os.tcgetattr(terminal_fd);
    try setRaw(terminal_fd);
    const stdin = io.getStdIn().reader();
    const char = try stdin.readByte();
    try os.tcsetattr(terminal_fd, os.TCSA.DRAIN, currentTermAttr);
    return char;
}

fn prompt(file: std.fs.File, username: []const u8, hostname: []const u8, path: []const u8) !void {
    const writer = file.writer();
    try writer.print("{s}{s}[{s}@{s}{s} {s}{s}]${s} ", .{
        BOLD,
        RED,
        username,
        hostname,
        GREEN,
        path,
        RED,
        DEFAULT,
    });
}

fn clearScreen(file: std.fs.File) !void {
    const writer = file.writer();
    try writer.writeAll("\x1B[2J\x1B[H");
}

fn prettyError(comptime fmt: []const u8, args: anytype) !void {
    const writer = io.getStdErr().writer();
    try writer.print("FakeBash: " ++ fmt ++ "\n", args);
}

fn eraseOneCharFromPrompt(file: std.fs.File) !void {
    const writer = file.writer();
    try writer.writeAll("\x1B[1D \x1B[1D");
}

pub fn main() !void {
    const stdout = io.getStdOut();
    const hostname = os.gethostname(&hostnameBuffer) catch "unavailable";

    var last_exit_code: u32 = 0;
    // buffer holding the string the user typed
    var promptStringBuffer = list(u8).init(alloc);
    defer promptStringBuffer.deinit();

    var commandArgumentsList = list([]const u8).init(alloc);
    defer commandArgumentsList.deinit();

    outer: while (true) {
        const cwd = os.getcwd(&cwdBuffer) catch "Location unknown";
        var dirIter = std.mem.splitBackwardsScalar(u8, cwd, '/');
        try prompt(stdout, "gabriel", hostname, dirIter.first());
        // Empty our buffer
        promptStringBuffer.clearRetainingCapacity();

        while (true) {
            const char = try getch(STDIN_FD);
            switch (char) {
                3 => { // handle ^C
                    try stdout.writer().writeAll("^C\n");
                    break;
                },
                4 => { // handle ^D
                    break :outer;
                },
                12 => { // Handle ^L
                    //try stdout.print("\x1B[2J\x1B[H", .{});
                    try clearScreen(stdout);
                    promptStringBuffer.clearRetainingCapacity();
                    break;
                },
                13 => { // handle enter key
                    try stdout.writer().print("\n", .{});
                    break;
                },
                127 => { // handle backspace
                    if (promptStringBuffer.items.len == 0) continue;
                    _ = promptStringBuffer.pop();
                    try eraseOneCharFromPrompt(stdout);
                    // TODO: erase the last char from the prompt
                },
                else => { // all other keys
                    try stdout.writer().print("{c}", .{char});
                    try promptStringBuffer.append(char);
                },
            }
        }
        // ----- Command parsing section
        if (promptStringBuffer.items.len == 0) continue; // Dont do anything if user just pressed enter
        var cmdArgs = split(u8, promptStringBuffer.items, ' ');
        while (cmdArgs.next()) |arg| {
            try commandArgumentsList.append(arg);
        }

        // ----- Fork and Exec section
        const pid = try os.fork();
        if (pid == 0) { // Here we are the child
            const e = std.process.execv(alloc, commandArgumentsList.items);
            switch (e) {
                error.FileNotFound => try prettyError("Unknown command: {s}", .{commandArgumentsList.items[0]}),
                error.InvalidExe => try prettyError("File exists but isn't executable", .{}),
                error.IsDir => try prettyError("Target is a directory, not an executable", .{}),
                else => try prettyError("Unhandled error!", .{}),
            }
            return;
        } else { // here we are the parrent
            last_exit_code = os.waitpid(pid, 0).status;
        }
        commandArgumentsList.clearRetainingCapacity();
    }

    std.debug.print("\nexit\n", .{});
}
