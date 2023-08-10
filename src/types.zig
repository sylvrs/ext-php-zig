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
pub const Array = Type{ .ptr = null, .type_mask = internal.MAY_BE_ARRAY };

pub fn resolveFromType(comptime T: type) TypeInfoError!TypeInfo {
    return switch (@typeInfo(T)) {
        .Null => TypeInfo.Null,
        .Void => TypeInfo.Void,
        .Bool => TypeInfo.Bool,
        .Int => TypeInfo.Long,
        .Float => TypeInfo.Double,
        .Pointer => |ptr| if (ptr.size == .slice and ptr.child == u8) TypeInfo.String else @compileError("Unsupported type: " ++ @typeName(T)),
        inline else => @compileError("Unsupported type: " ++ @typeName(T)),
    };
}

pub fn resolve(value: *zend.ZVal) TypeInfoError!TypeInfo {
    const type_info_value = value.u1.type_info;
    if (type_info_value < @intFromEnum(TypeInfo.Undefined) or type_info_value > @intFromEnum(TypeInfo.ExtendedArray)) {
        return TypeInfoError.Invalid;
    }
    return @as(TypeInfo, @enumFromInt(type_info_value));
}

pub fn mapToZendTypeInfo(comptime T: type) TypeInfo {
    return switch (@typeInfo(T)) {
        .Int => .Long,
        .Float => .Double,
        .Bool => .Bool,
        .Void => .Void,
        .Pointer => |ptr| if (ptr.size == .Slice and ptr.is_const and ptr.child == u8) .String else @compileError("unsupported pointer type: " ++ @typeName(ptr)),
        inline else => @compileError("unsupported type info: " ++ @typeName(T)),
    };
}

pub fn mapToZendType(comptime T: ?type) zend.Type {
    const current_type = T orelse return .Void;
    return switch (@typeInfo(current_type)) {
        .Int => Long,
        .Float => Double,
        .Bool => Bool,
        .Void => Void,
        .Pointer => |ptr| if (ptr.size == .Slice and ptr.is_const and ptr.child == u8) {
            return String;
        } else {
            return Array;
        },
        .ErrorUnion => |error_union| mapToZendType(error_union.payload),
        inline else => @compileError("unsupported type: " ++ @typeName(current_type)),
    };
}
