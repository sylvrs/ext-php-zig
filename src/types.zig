pub const internal = @import("internal.zig");
pub const zend = @import("zend.zig");

/// `Type` represents the structure of a Zend type.
pub const Type = internal.zend_type;
/// `TypeInfo` represents an associated type mask for a `Type`.
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

/// `Null` represents the `null` type.
pub const Null = Type{ .ptr = null, .type_mask = internal.MAY_BE_NULL };
/// `String` represents the `string` type.
pub const String = Type{ .ptr = null, .type_mask = internal.MAY_BE_STRING };
/// `Long` represents the `int` type. This is an `i64` in Zig.
pub const Long = Type{ .ptr = null, .type_mask = internal.MAY_BE_LONG };
/// `Double` represents the `float` type. This is an `f64` in Zig.
pub const Double = Type{ .ptr = null, .type_mask = internal.MAY_BE_DOUBLE };
/// `Array` represents the `array` type.
pub const Array = Type{ .ptr = null, .type_mask = internal.MAY_BE_ARRAY };
/// `Void` represents the `void` type. This is used for type-hinting only.
pub const Void = Type{ .ptr = null, .type_mask = internal.MAY_BE_VOID };
/// `Mixed` represents the `mixed` type. This is used for type-hinting only.
pub const Mixed = Type{ .ptr = null, .type_mask = internal.MAY_BE_ANY };
/// `Bool` represents the `bool` type. This is used for type-hinting only.
pub const Bool = Type{ .ptr = null, .type_mask = internal.MAY_BE_BOOL };
