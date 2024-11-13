const std = @import("std");
const microzig__pioasm = @import("microzig/port/raspberrypi/rp2xxx/src/hal/pio/assembler.zig");
const microzig__pioasm__encoder = @import("microzig/port/raspberrypi/rp2xxx/src/hal/pio/assembler/encoder.zig");
const microzig__pioasm__tokenizer = @import("microzig/port/raspberrypi/rp2xxx/src/hal/pio/assembler/tokenizer.zig");

const label__name: [32][]const u8 = .{
    "acid_burn",
    "apoc",

    "cereal_killer",
    "cisco",
    "coel",
    "crash_override",
    "csec",
    "cypher",

    "d3f4ult",
    "dolores_haze",
    "dozer",

    "ghost",

    "kaguya",

    "lord_nikon",

    "mobley",
    "morpheus",
    "mother",
    "mouse",

    "naix",
    "neo",

    "phantom_phreak",

    "romero",

    "sam_sepiol",
    "striker",
    "switch",

    "tank",
    "theo",
    "the_plague",
    "trenton",
    "trinity",

    "whistler",

    "zero_cool",
};

const ConfigSideset = struct {
    count: u3,
    pindirs: bool,
    optional: bool,
};
const Config = struct {
    hex__path: []const u8,
    name: ?[]const u8,
    start: ?u5,
    end: ?u5,
    sideset: ConfigSideset,
};

const ErrorCommand = error{
    StartEndIndexInvalid,
    StartIndexInvalid,
    EndIndexInvalid,
};
pub fn command(allocator: std.mem.Allocator, config: Config) !void {
    const asm__file = try std.fs.cwd().openFile(config.hex__path, .{});
    const asm__raw = try asm__file.readToEndAlloc(allocator, std.math.pow(usize, 2, 32));

    const asm__binary = try asmBinary(allocator, asm__raw);
    defer allocator.free(asm__binary);
    const instruction__array = try instructionArray(allocator, asm__binary);
    defer instruction__array.deinit();
    const jmp_target__array = try jmpTarget(allocator, instruction__array);
    defer jmp_target__array.deinit();

    const config__start: u5 = config.start orelse 0;
    const config__end: u5 = config.end orelse @intCast(instruction__array.items.len - 1);

    if (config__start > config__end) {
        try std.io.getStdOut().writer().print("Program start index must be smaller than or equal to the end index.\n", .{});
        return ErrorCommand.StartEndIndexInvalid;
    }
    if (instruction__array.items.len < config__start) {
        try std.io.getStdOut().writer().print("Program start index is out-of-bounds in the given hex file: len={d} start={d}.\n", .{ instruction__array.items.len, config__start });
        return ErrorCommand.StartIndexInvalid;
    }
    if (instruction__array.items.len < config__end) {
        try std.io.getStdOut().writer().print("Program end index is out-of-bounds in the given hex file: len={d} end={d}.\n", .{ instruction__array.items.len, config__end });
        return ErrorCommand.EndIndexInvalid;
    }

    try std.io.getStdErr().writer().print("[{X:0>2}] ", .{config__start});
    try std.io.getStdOut().writer().print(".program {s}\n", .{config.name orelse "default"});
    if (config.sideset.count > 0) {
        try std.io.getStdErr().writer().print("[{X:0>2}] ", .{config__start});
        try std.io.getStdOut().writer().print(".side_set {d}{s}{s}\n", .{ config.sideset.count, if (config.sideset.optional) " OPT" else "", if (config.sideset.pindirs) " PINDIRS" else "" });
    }
    for (0..config__start) |index| {
        try std.io.getStdErr().writer().print("[{X:0>2}] {X:0>4}\n", .{ index, asm__binary[index] });
    }
    for (instruction__array.items[config__start .. @as(u6, config__end) + 1], config__start..) |ins, index| {
        var encode__buffer: [1024]u8 = undefined;
        const encode: []const u8 = try switch (ins.tag) {
            .jmp => encodeJmp(ins, &encode__buffer, @intCast(instruction__array.items.len - 1)),
            .wait => encodeWait(ins, &encode__buffer),
            .in => encodeIn(ins, &encode__buffer),
            .out => encodeOut(ins, &encode__buffer),
            .push_pull => if (ins.payload.push._reserved1 == 0) encodePush(ins, &encode__buffer) else encodePull(ins, &encode__buffer),
            .mov => encodeMov(ins, &encode__buffer),
            .irq => encodeIrq(ins, &encode__buffer),
            .set => encodeSet(ins, &encode__buffer),
        };
        for (jmp_target__array.items) |jmp_target| {
            if (jmp_target == index) {
                try std.io.getStdErr().writer().print("[{X:0>2}] ", .{index});
                try std.io.getStdOut().writer().print("{s}__0x{X:0>2}:\n", .{ label__name[jmp_target], jmp_target });
            }
        }

        try std.io.getStdErr().writer().print("[{X:0>2}] ", .{index});
        try std.io.getStdOut().writer().print("    {s}", .{encode});
        const encode__delay_sideset = try encodeDelaySideset(encode__buffer[encode.len..], encode.len, ins.delay_side_set, config.sideset);
        try std.io.getStdOut().writer().print("{s}\n", .{encode__delay_sideset});
    }
    for (@as(u6, config__end) + 1..instruction__array.items.len) |index| {
        try std.io.getStdErr().writer().print("[{X:0>2}] {X:0>4}\n", .{ index, asm__binary[index] });
    }
}

const ErrorEncodeDelaySideSet = error{
    SidesetCountInvalid,
    InsEncodeTooLong,
};
fn encodeDelaySideset(buffer: []u8, ins_encode__len: usize, delay_sideset: u5, sideset__config: ConfigSideset) ![]const u8 {
    if (ins_encode__len > 40) {
        try std.io.getStdErr().writer().print("The instruction encoding is too long. This can only happen if there is a problem with the disassembler.\n", .{});
        return ErrorEncodeDelaySideSet.InsEncodeTooLong;
    }

    var sideset__raw: ?u5 = null;
    var delay__raw: ?u5 = null;
    var sideset_enable__raw: ?u1 = null;

    if (sideset__config.optional) {
        if (sideset__config.count > 4) {
            try std.io.getStdErr().writer().print("Sideset count is larger than 4. These values can only range between 0 and 4 (inclusive) when sideset is optional.\n", .{});
            return ErrorEncodeDelaySideSet.SidesetCountInvalid;
        }

        sideset__raw = if (sideset__config.count > 0) (delay_sideset & 0b01111) >> (4 - sideset__config.count) else 0;
        delay__raw = if (sideset__config.count == 5) 0 else delay_sideset & (@as(u5, 0b01111) >> sideset__config.count);
        sideset_enable__raw = @intCast((delay_sideset & 0b10000) >> 4);
    } else {
        if (sideset__config.count > 5) {
            try std.io.getStdErr().writer().print("Sideset count is larger than 5. These values can only range between 0 and 5 (inclusive) when sideset is not optional.\n", .{});
            return ErrorEncodeDelaySideSet.SidesetCountInvalid;
        }

        sideset__raw = if (sideset__config.count > 0) delay_sideset >> (5 - sideset__config.count) else 0;
        delay__raw = if (sideset__config.count == 5) 0 else delay_sideset & (@as(u5, 0b11111) >> sideset__config.count);
        sideset_enable__raw = if (sideset__config.count > 0) 1 else 0;
    }

    const space__len: usize = 36 - ins_encode__len;
    for (0..space__len) |idx| {
        buffer[idx] = ' ';
    }
    const buffer__start: usize = space__len;

    const side_encode: ?[]const u8 = if (sideset_enable__raw == 1) try std.fmt.bufPrint(buffer[buffer__start..], "SIDE 0x{X:0>2}", .{sideset__raw.?}) else null;
    const side_encode__len: usize = if (side_encode != null) side_encode.?.len else 0;
    const delay__encode: ?[]const u8 = if (delay__raw != 0) try std.fmt.bufPrint(buffer[buffer__start + side_encode__len ..], "{s}[{d}]", .{
        if (side_encode__len > 0) " " else "          ",
        delay__raw.?,
    }) else null;
    const delay__encode__len: usize = if (delay__encode != null) delay__encode.?.len else 0;

    if (side_encode__len + delay__encode__len == 0) {
        return buffer[0..0];
    } else {
        return buffer[0 .. buffer__start + side_encode__len + delay__encode__len];
    }
}

fn encodeJmp(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8, instruction__index_last: u5) ![]const u8 {
    const condition__text = switch (instruction.payload.jmp.condition) {
        .always => "",
        .x_is_zero => "!X ",
        .x_dec => "X-- ",
        .y_is_zero => "!Y ",
        .y_dec => "Y-- ",
        .x_is_not_y => "X!=Y ",
        .pin => "PIN ",
        .osre_not_empty => "!OSRE ",
    };
    return try std.fmt.bufPrint(buffer, "JMP     {s}{s}__0x{X:0>2}", .{
        condition__text,
        if (instruction.payload.jmp.address > instruction__index_last) "OUTSIDE_PROGRAM" else label__name[instruction.payload.jmp.address],
        instruction.payload.jmp.address,
    });
}

fn encodeWait(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const source__text = switch (instruction.payload.wait.source) {
        .gpio => "GPIO",
        .pin => "PIN",
        .irq => "IRQ",
    };
    const irq__rel: ?u1 = if (instruction.payload.wait.source == .irq) @intCast((instruction.payload.wait.index & 0b10000) >> 4) else null;
    return try std.fmt.bufPrint(buffer, "WAIT    {d} {s} {d}{s}", .{
        instruction.payload.wait.polarity,
        source__text,
        instruction.payload.wait.index,
        if (irq__rel != null) if (irq__rel.? != 0) " REL" else "" else "",
    });
}

fn encodeIn(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const source_text = switch (instruction.payload.in.source) {
        .pins => "PINS",
        .x => "X",
        .y => "Y",
        .null => "NULL",
        .isr => "ISR",
        .osr => "OSR",
    };
    return try std.fmt.bufPrint(buffer, "IN      {s}, {d}", .{
        source_text,
        if (instruction.payload.in.bit_count == 0) 32 else @as(u6, instruction.payload.in.bit_count),
    });
}

fn encodeOut(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const destination_text = switch (instruction.payload.out.destination) {
        .pins => "PINS",
        .x => "X",
        .y => "Y",
        .null => "NULL",
        .pindirs => "PINDIRS",
        .pc => "PC",
        .isr => "ISR",
        .exec => "EXEC",
    };
    return try std.fmt.bufPrint(buffer, "OUT     {s}, {d}", .{
        destination_text,
        if (instruction.payload.out.bit_count == 0) 32 else @as(u6, instruction.payload.out.bit_count),
    });
}

fn encodePush(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const if_full__text = if (instruction.payload.push.if_full == 1) "IFFULL " else "";
    const block__text = if (instruction.payload.push.block == 1) "BLOCK" else "NOBLOCK";
    return try std.fmt.bufPrint(buffer, "PUSH    {s}{s}", .{ if_full__text, block__text });
}

fn encodePull(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const if_empty__text = if (instruction.payload.pull.if_empty == 1) "IFEMPTY " else "";
    const block__text = if (instruction.payload.pull.block == 1) "BLOCK" else "NOBLOCK";
    return try std.fmt.bufPrint(buffer, "PULL    {s}{s}", .{ if_empty__text, block__text });
}

fn encodeMov(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const source__text = switch (instruction.payload.mov.source) {
        .pins => "PINS",
        .x => "X",
        .y => "Y",
        .null => "NULL",
        .status => "STATUS",
        .isr => "ISR",
        .osr => "OSR",
    };
    const operation__text = switch (instruction.payload.mov.operation) {
        .none => "",
        .invert => "~",
        .bit_reverse => "::",
    };
    const destination__text = switch (instruction.payload.mov.destination) {
        .pins => "PINS",
        .x => "X",
        .y => "Y",
        .exec => "EXEC",
        .pc => "PC",
        .isr => "ISR",
        .osr => "OSR",
    };
    return try std.fmt.bufPrint(buffer, "MOV     {s}, {s}{s}", .{ destination__text, operation__text, source__text });
}

fn encodeIrq(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const operation__text = ret__text: {
        if (instruction.payload.irq.wait == 0) {
            break :ret__text if (instruction.payload.irq.clear == 0) "NOWAIT" else "CLEAR";
        } else {
            break :ret__text if (instruction.payload.irq.clear == 0) "WAIT" else unreachable;
        }
    };
    const irq__idx: u4 = @intCast(instruction.payload.irq.index & 0b01111);
    const irq__rel: u1 = @intCast((instruction.payload.irq.index & 0b10000) >> 4);
    return try std.fmt.bufPrint(buffer, "IRQ     {s} {d}{s}", .{
        operation__text,
        irq__idx,
        if (irq__rel == 1) " REL" else "",
    });
}

fn encodeSet(instruction: microzig__pioasm__encoder.Instruction, buffer: []u8) ![]const u8 {
    const destination__text = switch (instruction.payload.set.destination) {
        .pins => "PINS",
        .x => "X",
        .y => "Y",
        .pindirs => "PINDIRS",
    };
    return try std.fmt.bufPrint(buffer, "SET     {s}, {d}", .{ destination__text, instruction.payload.set.data });
}

fn asmBinary(allocator: std.mem.Allocator, asm__hex: []const u8) ![]const u16 {
    const asm__bin__length = @divExact(asm__hex.len, 5);
    var asm__bin = try allocator.alloc(u16, asm__bin__length);
    errdefer allocator.free(asm__bin);
    var iterator__line = std.mem.splitScalar(u8, asm__hex, '\n');

    var line__idx: usize = 0;
    while (iterator__line.next()) |line| : (line__idx += 1) {
        if (line.len == 0) {
            continue;
        }
        try std.io.getStdErr().writer().print("Converting line to binary: idx={d} line=\"{s}\".\n", .{
            line__idx,
            line,
        });
        var instruction__binary: [2]u8 = undefined;
        const instruction = try std.fmt.hexToBytes(&instruction__binary, line);
        const instruction__big = std.mem.nativeToBig(u16, std.mem.bytesAsValue(u16, instruction).*);
        asm__bin[line__idx] = instruction__big;
        try std.io.getStdErr().writer().print("\"{s}\" -> 0x{X:0>4}.\n", .{
            line,
            asm__bin[line__idx],
        });
    }

    return asm__bin;
}

fn instructionArray(allocator: std.mem.Allocator, asm__binary: []const u16) !std.ArrayList(microzig__pioasm__encoder.Instruction) {
    var instruction__array = std.ArrayList(microzig__pioasm__encoder.Instruction).init(allocator);
    errdefer instruction__array.deinit();

    for (asm__binary, 0..) |ins, ins__idx| {
        const instruction__tag_raw: u3 = @intCast((ins & 0b1110_0000_0000_0000) >> (5 + 8));
        const instruction__tag: microzig__pioasm__encoder.Instruction.Tag = @enumFromInt(instruction__tag_raw);

        const instruction__payload: microzig__pioasm__encoder.Instruction.Payload = switch (instruction__tag) {
            .jmp => ret: {
                const condition__raw: u3 = @intCast((ins & 0b0000_0000_1110_0000) >> (0 + 5));
                const address__raw: u5 = @intCast((ins & 0b0000_0000_0001_1111) >> (0 + 0));

                break :ret .{
                    .jmp = .{
                        .condition = @enumFromInt(condition__raw),
                        .address = address__raw,
                    },
                };
            },
            .wait => ret: {
                const polarity__raw: u1 = @intCast((ins & 0b0000_0000_1000_0000) >> (0 + 7));
                const source__raw: u2 = @intCast((ins & 0b0000_0000_0110_0000) >> (0 + 5));
                const index__raw: u5 = @intCast((ins & 0b0000_0000_0001_1111) >> (0 + 0));

                break :ret .{
                    .wait = .{
                        .index = index__raw,
                        .source = @enumFromInt(source__raw),
                        .polarity = polarity__raw,
                    },
                };
            },
            .in => ret: {
                const source__raw: u3 = @intCast((ins & 0b0000_0000_1110_0000) >> (0 + 5));
                const bit_count__raw: u5 = @intCast((ins & 0b0000_0000_0001_1111) >> (0 + 0));

                break :ret .{
                    .in = .{
                        .bit_count = bit_count__raw,
                        .source = @enumFromInt(source__raw),
                    },
                };
            },
            .out => ret: {
                const destination__raw: u3 = @intCast((ins & 0b0000_0000_1110_0000) >> (0 + 5));
                const bit_count__raw: u5 = @intCast((ins & 0b0000_0000_0001_1111) >> (0 + 0));

                break :ret .{
                    .out = .{
                        .bit_count = bit_count__raw,
                        .destination = @enumFromInt(destination__raw),
                    },
                };
            },
            .push_pull => ret: {
                const push_pull: u1 = @intCast((ins & 0b0000_0000_1000_0000) >> (0 + 7));
                const zero__raw: u5 = @intCast((ins & 0b0000_0000_0001_1111) >> (0 + 0));
                const block__raw: u1 = @intCast((ins & 0b0000_0000_0010_0000) >> (0 + 5));
                if (zero__raw != 0) {
                    @panic("Invalid encoding of PUSH/PULL. Bits 0, 1, 2, 3, 4 must be 0.");
                }

                switch (push_pull) {
                    0 => {
                        const if_full__raw: u1 = @intCast((ins & 0b0000_0000_0100_0000) >> (0 + 6));

                        break :ret .{
                            .push = .{
                                ._reserved0 = 0,
                                .block = block__raw,
                                .if_full = if_full__raw,
                                ._reserved1 = 0,
                            },
                        };
                    },
                    1 => {
                        const if_empty__raw: u1 = @intCast((ins & 0b0000_0000_0100_0000) >> (0 + 6));

                        break :ret .{
                            .pull = .{
                                ._reserved0 = 0,
                                .block = block__raw,
                                .if_empty = if_empty__raw,
                                ._reserved1 = 1,
                            },
                        };
                    },
                }
            },
            .mov => ret: {
                const destination__raw: u3 = @intCast((ins & 0b0000_0000_1110_0000) >> (0 + 5));
                const operation__raw: u2 = @intCast((ins & 0b0000_0000_0001_1000) >> (0 + 3));
                const source__raw: u3 = @intCast((ins & 0b0000_0000_0000_0111) >> (0 + 0));

                break :ret .{
                    .mov = .{
                        .source = @enumFromInt(source__raw),
                        .operation = @enumFromInt(operation__raw),
                        .destination = @enumFromInt(destination__raw),
                    },
                };
            },
            .irq => ret: {
                const zero__raw: u1 = @intCast((ins & 0b0000_0000_1000_0000) >> (0 + 7));
                const clear__raw: u1 = @intCast((ins & 0b0000_0000_0100_0000) >> (0 + 6));
                const wait__raw: u1 = @intCast((ins & 0b0000_0000_0010_0000) >> (0 + 5));
                const index__raw: u5 = @intCast((ins & 0b0000_0000_0001_1111) >> (0 + 0));

                if (zero__raw != 0) {
                    @panic("Invalid encoding of IRQ. Bit 7 must be 0.");
                }
                if (clear__raw == 1 and wait__raw == 1) {
                    @panic("Invalid encoding of IRQ. IRQ cannot both CLEAR and WAIT at the same time.");
                }

                break :ret .{
                    .irq = .{
                        .index = index__raw,
                        .wait = wait__raw,
                        .clear = clear__raw,
                        .reserved = zero__raw,
                    },
                };
            },
            .set => ret: {
                const destination__raw: u3 = @intCast((ins & 0b0000_0000_1110_0000) >> (0 + 5));
                const data__raw: u5 = @intCast((ins & 0b0000_0000_0001_1111) >> (0 + 0));

                break :ret .{
                    .set = .{
                        .data = data__raw,
                        .destination = @enumFromInt(destination__raw),
                    },
                };
            },
        };

        const instruction: microzig__pioasm__encoder.Instruction = .{
            .payload = instruction__payload,
            .delay_side_set = @intCast((ins & 0b0001_1111_0000_0000) >> (0 + 8)),
            .tag = instruction__tag,
        };
        try instruction__array.append(instruction);
        try std.io.getStdErr().writer().print("Instruction: idx={d} tag={s}.\n", .{
            ins__idx,
            @tagName(instruction.tag),
        });
    }

    return instruction__array;
}

fn jmpTarget(allocator: std.mem.Allocator, instruction__array: std.ArrayList(microzig__pioasm__encoder.Instruction)) !std.ArrayList(u5) {
    var jmp_target__array = std.ArrayList(u5).init(allocator);
    errdefer jmp_target__array.deinit();
    outer: for (instruction__array.items) |instruction| {
        if (instruction.tag == .jmp) {
            for (jmp_target__array.items) |jmp_target| {
                if (instruction.payload.jmp.address == jmp_target) {
                    continue :outer;
                }
            }
            try jmp_target__array.append(instruction.payload.jmp.address);
        }
    }
    return jmp_target__array;
}
