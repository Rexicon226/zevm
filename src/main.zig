const std = @import("std");
const b = @import("bindings.zig");

const STACK_SIZE = 1024;

const OpCode = enum(u8) {
    STOP = 0x00,
    ADD = 0x01,
    MUL = 0x02,
    SUB = 0x03,
    PUSH1 = 0x60,
};

const Op = union(OpCode) {
    STOP,
    ADD,
    MUL,
    SUB,
    PUSH1: u8,

    fn returnType(comptime op: Op) type {
        return switch (op) {
            .STOP > void, .ADD => u256,
            .PUSH1 => void,
            else => @compileError("TODO: returnType " ++ @tagName(op)),
        };
    }
};

pub fn main() !void {
    // const args = std.os.argv;
    // if (args.len != 2) @panic("evm [input.hex]");

    // const bin_path = std.mem.span(args[1]);
    // const bytes = try std.fs.cwd().readFileAlloc(std.heap.c_allocator, bin_path, 1 * 1024);
    // defer std.heap.c_allocator.free(bytes);

    const bytes = &[_]u8{
        0x60, 0x02,
        0x00,
    };

    var ops: [2400]Op = undefined;
    var length: usize = 0;

    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        var code: Op = undefined;
        const op: OpCode = @enumFromInt(bytes[i]);
        switch (op) {
            .PUSH1 => {
                i += 1;
                code = .{ .PUSH1 = bytes[i] };
            },
            inline else => |o| code = o,
        }
        ops[length] = code;
        length += 1;
    }

    std.debug.print("input ops:\n", .{});
    for (ops[0..length]) |op| {
        std.debug.print("{s}\n", .{@tagName(op)});
    }

    initTarget();

    const context = b.LLVMContextCreate();
    const mod = b.LLVMModuleCreateWithNameInContext("EVM", context);
    createIR(ops[0..length], mod);

    // uncomment to dump the LLVM IR
    b.LLVMDumpModule(mod);

    var ee: b.LLVMExecutionEngineRef = undefined;
    if (b.LLVMCreateExecutionEngineForModule(&ee, mod, null) == 1) {
        std.debug.print("failed to create EE\n", .{});
        return;
    }

    const address = b.LLVMGetFunctionAddress(ee, "evm_main");
    if (address == 0) {
        std.debug.print("function 'evm_main' not found\n", .{});
        return;
    } else {
        var result: u256 = 0;
        const main_func: *const fn (*u256) callconv(.C) void = @ptrFromInt(address);
        main_func(&result);
        std.debug.print("Result: {d}\n", .{result});
    }
}

fn initTarget() void {
    _ = b.LLVMInitializeNativeTarget();
    _ = b.LLVMInitializeNativeAsmPrinter();
    _ = b.LLVMInitializeNativeAsmParser();
}

// fn pop(sa: *[1024]u256, sp: *u32) u256
fn genPop(builder: b.LLVMBuilderRef, mod: b.LLVMModuleRef) void {
    const uint256 = b.LLVMIntType(256);

    const sa_ty = b.LLVMArrayType(uint256, STACK_SIZE);
    const sa_ptr_ty = b.LLVMPointerType(sa_ty, 0);
    var func_args = [_]b.LLVMTypeRef{
        sa_ptr_ty,
        b.LLVMPointerType(b.LLVMInt32Type(), 0),
    };
    const func_ty = b.LLVMFunctionType(uint256, &func_args, 2, 0);
    const func = b.LLVMAddFunction(mod, "pop", func_ty);

    const entry = b.LLVMAppendBasicBlock(func, "EntryBlock");
    b.LLVMPositionBuilderAtEnd(builder, entry);

    const sa = b.LLVMGetParam(func, 0);
    const sp = b.LLVMGetParam(func, 1);

    const sp_load = b.LLVMBuildLoad2(builder, b.LLVMInt32Type(), sp, "sp_load");
    var gep_params = [_]b.LLVMValueRef{
        b.LLVMConstInt(b.LLVMInt32Type(), 0, 0),
        sp_load,
    };
    const ptr = b.LLVMBuildInBoundsGEP2(builder, sa_ty, sa, &gep_params, 2, "gep_ptr");
    const value = b.LLVMBuildLoad2(builder, uint256, ptr, "gep_load");

    const dec = b.LLVMBuildSub(builder, sp_load, b.LLVMConstInt(b.LLVMInt32Type(), 1, 0), "sp_dec");
    _ = b.LLVMBuildStore(builder, dec, sp);

    _ = b.LLVMBuildRet(builder, value);
}

// fn push(sa: *[1024]u256, sp: *u32, val: u256) void
fn genPush(builder: b.LLVMBuilderRef, mod: b.LLVMModuleRef) void {
    const uint256 = b.LLVMIntType(256);
    const sa_ty = b.LLVMArrayType(uint256, STACK_SIZE);
    const sa_ptr_ty = b.LLVMPointerType(sa_ty, 0);

    var func_args = [_]b.LLVMTypeRef{
        sa_ptr_ty,
        b.LLVMPointerType(b.LLVMInt32Type(), 0),
        uint256,
    };

    const func_ty = b.LLVMFunctionType(b.LLVMVoidType(), &func_args, 3, 0);
    const func = b.LLVMAddFunction(mod, "push", func_ty);

    const entry = b.LLVMAppendBasicBlock(func, "EntryBlock");
    b.LLVMPositionBuilderAtEnd(builder, entry);

    const sa = b.LLVMGetParam(func, 0);
    const sp = b.LLVMGetParam(func, 1);
    const value = b.LLVMGetParam(func, 2);

    const sp_load = b.LLVMBuildLoad2(builder, b.LLVMInt32Type(), sp, "sp_load");
    const inc = b.LLVMBuildAdd(builder, sp_load, b.LLVMConstInt(b.LLVMInt32Type(), 1, 0), "sp_inc");
    _ = b.LLVMBuildStore(builder, inc, sp);

    var gep_params = [_]b.LLVMValueRef{
        b.LLVMConstInt(b.LLVMInt32Type(), 0, 0),
        inc,
    };
    const ptr = b.LLVMBuildInBoundsGEP2(builder, sa_ty, sa, &gep_params, 2, "gep_ptr");
    _ = b.LLVMBuildStore(builder, value, ptr);

    _ = b.LLVMBuildRet(builder, null);
}

fn callFunction(
    comptime name: [:0]const u8,
    comptime arg_count: usize,
    comptime is_void: bool,
) fn (b.LLVMBuilderRef, b.LLVMModuleRef, []const b.LLVMValueRef) b.LLVMValueRef {
    const S = struct {
        fn call(
            builder: b.LLVMBuilderRef,
            mod: b.LLVMModuleRef,
            in_args: []const b.LLVMValueRef,
        ) b.LLVMValueRef {
            const func = b.LLVMGetNamedFunction(mod, name.ptr);
            const func_ty = b.LLVMGlobalGetValueType(func);

            var args = in_args[0..arg_count].*;

            const ret_name = if (is_void) "" else name ++ "_return";
            return b.LLVMBuildCall2(builder, func_ty, func, &args, arg_count, ret_name);
        }
    };
    return S.call;
}

fn pop(
    builder: b.LLVMBuilderRef,
    mod: b.LLVMModuleRef,
    in_args: []const b.LLVMValueRef,
) b.LLVMValueRef {
    return callFunction("pop", 2, false)(builder, mod, in_args);
}

fn push(
    builder: b.LLVMBuilderRef,
    mod: b.LLVMModuleRef,
    in_args: []const b.LLVMValueRef,
) b.LLVMValueRef {
    return callFunction("push", 3, true)(builder, mod, in_args);
}

fn createIR(bytes: []const Op, mod: b.LLVMModuleRef) void {
    const builder = b.LLVMCreateBuilder();
    genPop(builder, mod);
    genPush(builder, mod);

    const uint256 = b.LLVMIntType(256);
    const ptr_uint256 = b.LLVMPointerType(uint256, 0);
    var params = [_]b.LLVMTypeRef{ptr_uint256};
    const func_ty = b.LLVMFunctionType(b.LLVMVoidType(), &params, 1, 0);
    const func = b.LLVMAddFunction(mod, "evm_main", func_ty);

    const entry_block = b.LLVMAppendBasicBlock(func, "EntryBlock");
    b.LLVMPositionBuilderAtEnd(builder, entry_block);

    const sa_ty = b.LLVMArrayType(uint256, STACK_SIZE);
    const stack_array = b.LLVMBuildAlloca(builder, sa_ty, "stack");
    const stack_pointer = b.LLVMBuildAlloca(builder, b.LLVMInt32Type(), "sp");
    _ = b.LLVMBuildStore(builder, b.LLVMConstInt(b.LLVMInt32Type(), 0, 0), stack_pointer);

    for (bytes) |op| {
        switch (op) {
            .STOP => {
                break;
            },
            .ADD,
            .MUL,
            => {
                const rhs = pop(builder, mod, &.{ stack_array, stack_pointer });
                const lhs = pop(builder, mod, &.{ stack_array, stack_pointer });

                const result = switch (op) {
                    .ADD => b.LLVMBuildAdd(builder, lhs, rhs, "sum"),
                    .MUL => b.LLVMBuildMul(builder, lhs, rhs, "product"),
                    else => unreachable,
                };

                _ = push(builder, mod, &.{ stack_array, stack_pointer, result });
            },
            .PUSH1 => |value| {
                _ = push(
                    builder,
                    mod,
                    &.{
                        stack_array,
                        stack_pointer,
                        b.LLVMConstInt(uint256, value, 0),
                    },
                );
            },
            else => std.debug.panic("TODO: {s}", .{@tagName(op)}),
        }
    }

    const out_ptr = b.LLVMGetParam(func, 0);
    const ret = pop(builder, mod, &.{ stack_array, stack_pointer });
    _ = b.LLVMBuildStore(builder, ret, out_ptr);
    _ = b.LLVMBuildRet(builder, null);
}
