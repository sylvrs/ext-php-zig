pub const internal = @import("internal.zig");
pub const zend = @import("zend.zig");
pub const Type = internal.zend_type;
pub const TypeInfo = enum(u32) {
    Undefined = internal.IS_UNDEF,
    Null = internal.IS_NULL,
    False = internal.IS_FALSE,
    True = internal.IS_TRUE,
    Long = internal.IS_LONG,
    Double = internal.IS_DOUBLE,
    String = internal.IS_STRING,
    Array = internal.IS_ARRAY,
    Object = internal.IS_OBJECT,
    Resource = internal.IS_RESOURCE,
    Reference = internal.IS_REFERENCE,
    Constant = internal.IS_CONSTANT_AST,
    // Fake types used for typehinting
    Callable = internal.IS_CALLABLE,
    Iterable = internal.IS_ITERABLE,
    Void = internal.IS_VOID,
    Static = internal.IS_STATIC,
    Mixed = internal.IS_MIXED,
    Never = internal.IS_NEVER,
    // Used for casting
    Bool = internal._IS_BOOL,
    Number = internal._IS_NUMBER,
    // Extended types (refcounted)
    ExtendedString = internal.IS_STRING_EX,
    ExtendedArray = internal.IS_ARRAY_EX,
    ExtendedObject = internal.IS_OBJECT_EX,
    ExtendedResource = internal.IS_RESOURCE_EX,
    ExtendedReference = internal.IS_REFERENCE_EX,
    ExtendedConstant = internal.IS_CONSTANT_AST_EX,

    pub fn asValue(self: TypeInfo) u32 {
        return @intFromEnum(self);
    }
};
pub const TypeInfoError = error{Invalid};

pub const Null = Type{ .ptr = null, .type_mask = internal.MAY_BE_NULL };
pub const Void = Type{ .ptr = null, .type_mask = internal.MAY_BE_VOID };
pub const String = Type{ .ptr = null, .type_mask = internal.MAY_BE_STRING };
pub const Mixed = Type{ .ptr = null, .type_mask = internal.MAY_BE_ANY };
pub const Bool = Type{ .ptr = null, .type_mask = internal.MAY_BE_BOOL };
pub const Long = Type{ .ptr = null, .type_mask = internal.MAY_BE_LONG };
pub const Double = Type{ .ptr = null, .type_mask = internal.MAY_BE_DOUBLE };

pub fn resolve(value: *zend.ZVal) TypeInfoError!TypeInfo {
    const type_info_value = value.u1.type_info;
    if (type_info_value < @intFromEnum(TypeInfo.Undefined) or type_info_value > @intFromEnum(TypeInfo.ExtendedArray)) {
        return TypeInfoError.Invalid;
    }
    return @as(TypeInfo, @enumFromInt(type_info_value));
}
