//! Assembles EVM bytecode from ZON input files

const std = @import("std");
const Ast = std.zig.Ast;
const assert = std.debug.assert;

const main_import = @import("main.zig");
const OpCode = main_import.OpCode;
const Op = main_import.Op;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    defer _ = gpa.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 3) @panic("evasm [input.zon] [out.hex]");

    const input = args[1];

    const bytes = try std.fs.cwd().readFileAllocOptions(
        allocator,
        input,
        1024 * 1024,
        null,
        @alignOf(u8),
        0,
    );
    defer allocator.free(bytes);

    var ast = try Ast.parse(allocator, bytes, .zon);
    defer ast.deinit(allocator);

    if (ast.errors.len > 0) {
        var stderr = std.io.getStdErr();
        for (ast.errors) |err| {
            try ast.renderError(err, stderr.writer());
        }
        fail("\nound errors in the input zon, exiting\n", .{});
    }

    const token_tags = ast.tokens.items(.tag);

    const node_tags = ast.nodes.items(.tag);
    const node_datas = ast.nodes.items(.data);
    // const main_tokens = ast.nodes.items(.main_token);

    assert(node_tags[0] == .root);
    const main_node_index = node_datas[0].lhs;

    var buf: [2]Ast.Node.Index = undefined;
    const array_init = ast.fullArrayInit(&buf, main_node_index) orelse {
        return fail("expected top level expression to be an array\n", .{});
    };

    var operations = std.ArrayList(Op).init(allocator);
    defer operations.deinit();

    for (array_init.ast.elements) |elem_init| {
        switch (node_tags[elem_init]) {
            // .POP,
            .enum_literal => {
                const name_token = ast.firstToken(elem_init) + 1;
                const field_name = token_tags[name_token];
                assert(field_name == .identifier);
                const ident_name = ast.tokenSlice(name_token);
                const op_code = std.meta.stringToEnum(OpCode, ident_name) orelse {
                    fail("expected enum_literal opcode, got '{s}'\n", .{ident_name});
                };

                switch (op_code) {
                    .PUSH1 => fail(
                        "the '{s}' opcode requires a payload, use '.{{ .'{[0]s}' = }} syntax instead",
                        .{ident_name},
                    ),
                    inline else => |o| try operations.append(o),
                }
            },
            // .{ .PUSH = 0x02 },
            .struct_init_dot_two => {
                var sub_buf: [2]Ast.Node.Index = undefined;
                const struct_init = ast.fullStructInit(&sub_buf, elem_init) orelse unreachable;
                if (struct_init.ast.fields.len != 1) fail(
                    "union payload init syntax needs to have only one field inside, found '{d}'",
                    .{struct_init.ast.fields.len},
                );

                for (struct_init.ast.fields) |field| {
                    const first_token = ast.firstToken(field);
                    const name_token = first_token - 2;
                    const field_name = token_tags[name_token];
                    assert(field_name == .identifier);
                    const ident_name = ast.tokenSlice(name_token);
                    const op_code = std.meta.stringToEnum(OpCode, ident_name) orelse {
                        fail("expected enum_literal opcode, got '{s}'\n", .{ident_name});
                    };
                    if (node_tags[field] != .number_literal) {
                        fail("expected number literal payload, not '{s}'", .{@tagName(node_tags[field])});
                    }

                    const number_slice = ast.tokenSlice(first_token);
                    const result = std.zig.parseNumberLiteral(number_slice);
                    if (result != .int) {
                        fail("expected number_literal to fit into a u64, found '{s}'", .{@tagName(result)});
                    }

                    switch (op_code) {
                        inline .PUSH1,
                        => |op| {
                            const T = std.meta.TagPayload(Op, op);
                            const val = std.math.cast(T, result.int) orelse fail(
                                "'{s}' has a payload of type '{s}', but found '{d}' value which cannot fit",
                                .{ @tagName(op_code), @typeName(T), result.int },
                            );

                            const inst: Op = @unionInit(Op, @tagName(op), val);
                            try operations.append(inst);
                        },
                        else => fail(
                            "found '{s}' opcode with payload, when it doesn't have one",
                            .{@tagName(op_code)},
                        ),
                    }
                }
            },
            else => fail("root array contains {s}", .{@tagName(node_tags[elem_init])}),
        }
    }

    const out_path = args[2];
    try dumpOpCodes(out_path, operations.items);
}

fn dumpOpCodes(out_path: []const u8, operations: []const Op) !void {
    const file = try std.fs.cwd().createFile(out_path, .{ .lock = .exclusive });
    const file_writer = file.writer();
    var bw = std.io.bufferedWriter(file_writer);
    const writer = bw.writer();

    for (operations) |op| {
        try writer.writeByte(@intFromEnum(std.meta.activeTag(op)));

        switch (op) {
            .PUSH1 => |val| try writer.writeByte(val),
            else => {},
        }
    }

    try bw.flush();
    file.close();
}

fn fail(comptime fmt: []const u8, args: anytype) noreturn {
    var stderr = std.io.getStdErr().writer();
    stderr.print(fmt, args) catch @panic("failed to print to stderr");
    std.posix.exit(1);
}
