pub const std = @import("std");
pub const internal = @import("internal.zig");
pub const types = @import("types.zig");

// Zend Options
pub const Debug: u1 = 1;
pub const ThreadSafe: u1 = 1;
pub const ModuleAPI = 20220829;

pub const ModuleEntry = internal._zend_module_entry;
pub const FunctionEntry = internal._zend_function_entry;
pub const InternalArgInfo = internal._zend_internal_arg_info;
pub const ArgInfo = internal._zend_arg_info;
pub const ExecuteData = internal._zend_execute_data;
pub const ZVal = internal._zval_struct;
pub const String = internal._zend_string;
pub const Value = internal._zend_value;
pub const Result = internal.zend_result;
pub const Type = types.Type;
pub const ClassEntry = internal._zend_class_entry;

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
