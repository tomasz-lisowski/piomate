const std = @import("std");
const disassemble = @import("disassemble.zig");
const args = @import("args");

pub fn main() !void {
    var allocator__gp = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = allocator__gp.allocator();

    const options = try args.parseWithVerbForCurrentProcess(
        struct {},
        union(enum) {
            help: struct {},
            disassemble: struct {
                help: bool = false,
                hex: ?[]const u8 = null,
                name: ?[]const u8 = null,
                start: ?u5 = null,
                end: ?u5 = null,
                @"sideset-count": ?u3 = null,
                @"sideset-pindirs": ?bool = null,
                @"sideset-optional": ?bool = null,
            },
        },
        allocator,
        .print,
    );
    defer options.deinit();

    if (options.positionals.len != 0) {
        try std.io.getStdErr().writer().print("Expected no positional arguments: actual={d} expected={d}. Ask for help using the \"help\" command.\n", .{ options.positionals.len, 0 });
        return;
    }

    if (options.verb) |verb| {
        switch (verb) {
            .help => |_| {
                try std.io.getStdErr().writer().print("Usage: {s} [ help | disassemble --help ].\n", .{options.executable_name orelse "<path/to/executable>"});
                return;
            },
            .disassemble => |verb__options| {
                if (verb__options.help == true) {
                    try std.io.getStdErr().writer().print(
                        \\Usage: {s} [ help | disassemble --help --hex=<path/to/asm.hex> --name=<program_name> --start=<program_start_index> --end=<program_end_index> --sideset-count=<bit_count> --sideset-optional=<true_false> --sideset-pindirs=<true_false> ].
                        \\- "--sideset-count" refers to the 'number' you set in your ".side_set <number>" directive.
                        \\- "--sideset-optional" refers to the presence of the 'OPT' parameter in your ".side_set <number> OPT" directive.
                        \\- "--sideset-pindirs" refers to the presence of the 'PINDIRS' parameter in your ".side_set <number> PINDIRS" directive.
                        \\
                    , .{options.executable_name orelse "<path/to/executable>"});
                    return;
                } else {
                    if (verb__options.hex == null) {
                        try std.io.getStdErr().writer().print("Path to the hex file is missing. Ask for help using the \"help\" command.\n", .{});
                        return;
                    }
                    if (verb__options.@"sideset-count" == null) {
                        try std.io.getStdErr().writer().print("Sideset count missing. Ask for help using the \"help\" command.\n", .{});
                        return;
                    }
                    if (verb__options.@"sideset-pindirs" == null) {
                        try std.io.getStdErr().writer().print("Sideset pindirs missing. Ask for help using the \"help\" command.\n", .{});
                        return;
                    }
                    if (verb__options.@"sideset-optional" == null) {
                        try std.io.getStdErr().writer().print("Sideset optional missing. Ask for help using the \"help\" command.\n", .{});
                        return;
                    }
                    try disassemble.command(allocator, .{
                        .hex__path = verb__options.hex.?,
                        .name = verb__options.name,
                        .start = verb__options.start,
                        .end = verb__options.end,
                        .sideset = .{
                            .count = verb__options.@"sideset-count".?,
                            .pindirs = verb__options.@"sideset-pindirs".?,
                            .optional = verb__options.@"sideset-optional".?,
                        },
                    });
                    return;
                }
            },
        }
        try std.io.getStdErr().writer().print("Nothing was done, make sure to specify correct arguments. When in doubt, ask for help with the \"help\" command.\n", .{});
        return;
    }
    try std.io.getStdErr().writer().print("Ask for help with the \"help\" command.\n", .{});
}
