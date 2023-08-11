const internal = @import("internal.zig");

/// `ModuleEntry` represents the layout of a PHP extension module.
pub const ModuleEntry = internal._zend_module_entry;
/// `ExecuteData` represents the layout of a PHP call frame.
pub const ExecuteData = internal._zend_execute_data;
/// `ZVal` represents the layout of a PHP value.
pub const ZVal = internal._zval_struct;
/// `InternalArgInfo` represents the layout of a PHP function argument's metadata.
pub const InternalArgInfo = internal._zend_internal_arg_info;

const callFrameSlot = (alignedSize(ExecuteData) + alignedSize(ZVal) - 1) / alignedSize(ZVal);

/// `resolveZVal` returns a pointer to the `ZVal` at the given offset from the given `ExecuteData`.
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
