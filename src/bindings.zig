const builtin = @import("builtin");

pub const LLVMBool = c_int;
pub const LLVMOpaqueContext = opaque {};
pub const LLVMContextRef = ?*LLVMOpaqueContext;

const native = switch (builtin.cpu.arch) {
    .x86_64 => struct {
        const LLVMInitializeTargetInfo = @extern(
            *const fn () callconv(.C) void,
            .{ .name = "LLVMInitializeX86TargetInfo" },
        );

        const LLVMInitializeTarget = @extern(
            *const fn () callconv(.C) void,
            .{ .name = "LLVMInitializeX86Target" },
        );

        const LLVMInitializeTargetMC = @extern(
            *const fn () callconv(.C) void,
            .{ .name = "LLVMInitializeX86TargetMC" },
        );

        const LLVMInitializeAsmPrinter = @extern(
            *const fn () callconv(.C) void,
            .{ .name = "LLVMInitializeX86AsmPrinter" },
        );

        const LLVMInitializeAsmParser = @extern(
            *const fn () callconv(.C) void,
            .{ .name = "LLVMInitializeX86AsmParser" },
        );
    },
    else => @compileError("TODO native: " ++ @tagName(builtin.cpu.arch)),
};

pub fn LLVMInitializeNativeTarget() LLVMBool {
    native.LLVMInitializeTargetInfo();
    native.LLVMInitializeTarget();
    native.LLVMInitializeTargetMC();
    return 0;
}

pub fn LLVMInitializeNativeAsmPrinter() LLVMBool {
    native.LLVMInitializeAsmPrinter();
    return 0;
}

pub fn LLVMInitializeNativeAsmParser() LLVMBool {
    native.LLVMInitializeAsmParser();
    return 0;
}

// core

pub const LLVMOpaqueModule = opaque {};
pub const LLVMModuleRef = ?*LLVMOpaqueModule;

pub const LLVMOpaqueBuilder = opaque {};
pub const LLVMBuilderRef = ?*LLVMOpaqueBuilder;

pub const LLVMOpaqueType = opaque {};
pub const LLVMTypeRef = ?*LLVMOpaqueType;

pub const LLVMOpaqueValue = opaque {};
pub const LLVMValueRef = ?*LLVMOpaqueValue;

pub const LLVMOpaqueBasicBlock = opaque {};
pub const LLVMBasicBlockRef = ?*LLVMOpaqueBasicBlock;

pub const LLVMOpaqueError = opaque {};
pub const LLVMErrorRef = ?*LLVMOpaqueError;

pub extern fn LLVMGetErrorMessage(Err: LLVMErrorRef) [*c]u8;

pub extern fn LLVMContextCreate() LLVMContextRef;
pub extern fn LLVMModuleCreateWithNameInContext(ModuleID: [*:0]const u8, C: LLVMContextRef) LLVMModuleRef;
pub extern fn LLVMCreateBuilder() LLVMBuilderRef;
pub extern fn LLVMFunctionType(ReturnType: LLVMTypeRef, ParamTypes: [*c]LLVMTypeRef, ParamCount: c_uint, IsVarArg: LLVMBool) LLVMTypeRef;

pub extern fn LLVMInt32Type() LLVMTypeRef;
pub extern fn LLVMInt64Type() LLVMTypeRef;
pub extern fn LLVMIntType(NumBits: c_uint) LLVMTypeRef;
pub extern fn LLVMArrayType(ElementType: LLVMTypeRef, ElementCount: c_uint) LLVMTypeRef;
pub extern fn LLVMPointerType(ElementType: LLVMTypeRef, AddressSpace: c_uint) LLVMTypeRef;
pub extern fn LLVMVoidType() LLVMTypeRef;

pub extern fn LLVMGetParam(Fn: LLVMValueRef, Index: c_uint) LLVMValueRef;
pub extern fn LLVMGetNamedFunction(M: LLVMModuleRef, Name: [*:0]const u8) LLVMValueRef;

pub extern fn LLVMAddFunction(M: LLVMModuleRef, Name: [*:0]const u8, FunctionTy: LLVMTypeRef) LLVMValueRef;

pub extern fn LLVMGlobalGetValueType(Global: LLVMValueRef) LLVMTypeRef;

pub extern fn LLVMAppendBasicBlock(Fn: LLVMValueRef, Name: [*:0]const u8) LLVMBasicBlockRef;
pub extern fn LLVMPositionBuilderAtEnd(Builder: LLVMBuilderRef, Block: LLVMBasicBlockRef) void;

pub extern fn LLVMBuildArrayAlloca(LLVMBuilderRef, Ty: LLVMTypeRef, Val: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildAlloca(LLVMBuilderRef, Ty: LLVMTypeRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildStore(LLVMBuilderRef, Val: LLVMValueRef, Ptr: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMBuildLoad2(LLVMBuilderRef, Ty: LLVMTypeRef, PointerVal: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildAdd(LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildSub(LLVMBuilderRef, LHS: LLVMValueRef, RHS: LLVMValueRef, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildRet(LLVMBuilderRef, V: LLVMValueRef) LLVMValueRef;
pub extern fn LLVMBuildCall2(LLVMBuilderRef, LLVMTypeRef, Fn: LLVMValueRef, Args: [*c]LLVMValueRef, NumArgs: c_uint, Name: [*:0]const u8) LLVMValueRef;
pub extern fn LLVMBuildInBoundsGEP2(B: LLVMBuilderRef, Ty: LLVMTypeRef, Pointer: LLVMValueRef, Indices: [*c]LLVMValueRef, NumIndices: c_uint, Name: [*:0]const u8) LLVMValueRef;

pub extern fn LLVMConstInt(IntTy: LLVMTypeRef, N: c_ulonglong, SignExtend: LLVMBool) LLVMValueRef;
pub extern fn LLVMConstNull(Ty: LLVMTypeRef) LLVMValueRef;

pub extern fn LLVMDumpModule(M: LLVMModuleRef) void;

// EE
pub const LLVMOpaqueExecutionEngine = opaque {};
pub const LLVMExecutionEngineRef = ?*LLVMOpaqueExecutionEngine;

pub extern fn LLVMGetFunctionAddress(EE: LLVMExecutionEngineRef, Name: [*c]const u8) u64;
pub extern fn LLVMCreateExecutionEngineForModule(OutEE: [*c]LLVMExecutionEngineRef, M: LLVMModuleRef, OutError: [*c][*c]u8) LLVMBool;

// Target
pub const LLVMOpaqueTargetMachine = opaque {};
pub const LLVMTargetMachineRef = ?*LLVMOpaqueTargetMachine;

pub const LLVMCodeGenFileType = enum(c_int) {
    LLVMAssemblyFile,
    LLVMObjectFile,
};

pub const LLVMOpaqueMemoryBuffer = opaque {};
pub const LLVMMemoryBufferRef = ?*LLVMOpaqueMemoryBuffer;

pub extern fn LLVMTargetMachineEmitToMemoryBuffer(T: LLVMTargetMachineRef, M: LLVMModuleRef, codegen: LLVMCodeGenFileType, ErrorMessage: [*c][*c]u8, OutMemBuf: [*c]LLVMMemoryBufferRef) LLVMBool;
pub extern fn LLVMGetHostCPUFeatures() [*c]u8;
