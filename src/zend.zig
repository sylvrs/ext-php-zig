pub const std = @import("std");
pub const internal = @import("internal.zig");
pub const Module = @import("Module.zig");
pub const types = @import("types.zig");

// Zend Options
pub const Debug: bool = true;
pub const ThreadSafe: bool = true;
pub const ModuleAPI = 20220829;

pub const ModuleEntry = internal._zend_module_entry;
pub const FunctionEntry = internal._zend_function_entry;
pub const InternalArgInfo = internal._zend_internal_arg_info;
pub const ArgInfo = internal._zend_arg_info;
pub const ExecuteData = internal._zend_execute_data;
pub const ZVal = internal._zval_struct;
pub const InternalString = internal._zend_string;

pub const Value = internal._zend_value;
pub const Result = internal.zend_result;
pub const Type = types.Type;
pub const ClassEntry = internal._zend_class_entry;
pub const Object = internal._zend_object;

pub const RefCounted = internal._zend_refcounted_h;
pub const Array = internal._zend_array;
pub const HashTable = internal.HashTable;

const callFrameSlot = (alignedSize(ExecuteData) + alignedSize(ZVal) - 1) / alignedSize(ZVal);

pub fn resolveZVal(execute_data: *ExecuteData, offset: usize) *ZVal {
    return ptrOffset(ZVal, @intFromPtr(execute_data), callFrameSlot + offset);
}

fn ptrOffset(comptime T: type, ptr: usize, offset: usize) *T {
    return @ptrFromInt(ptr + (offset * alignedSize(T)));
}

fn alignedSize(comptime T: type) usize {
    const size: usize = @sizeOf(T);
    return (size + internal.ZEND_MM_ALIGNMENT - 1) & internal.ZEND_MM_ALIGNMENT_MASK;
}

fn allocFlexibleArrayMember(allocator: std.mem.Allocator, comptime T: type, comptime E: type, value: []const E) !*T {
    const bytes = try allocator.alignedAlloc(
        u8,
        @alignOf(T),
        @sizeOf(T) + (value.len * @sizeOf(E)),
    );
    errdefer allocator.free(bytes);
    const ptr = std.mem.bytesAsValue(T, bytes[0..@sizeOf(T)]);
    ptr.*.gc.u.type_info = types.TypeInfo.String.asValue();
    ptr.*.len = value.len;
    var val_ptr: [*]E = &ptr.*.val;
    @memcpy(val_ptr, value);
    return ptr;
}

pub fn createString(allocator: std.mem.Allocator, value: []const u8) !*InternalString {
    return allocFlexibleArrayMember(
        allocator,
        InternalString,
        u8,
        value,
    );
}
