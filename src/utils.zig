/// `map` is a function that takes a return type, an array of values, and a function that takes a value and returns a value of the return type.
pub fn map(comptime values: anytype, comptime func: anytype) [values.len](@typeInfo(@TypeOf(func)).Fn.return_type.?) {
    // `T` is the type of the values in the array.
    const T: type = switch (@typeInfo(@TypeOf(values))) {
        .Array => |array| array.child,
        .Pointer => |ptr| ptr.child,
        inline else => @compileError("map function must take an array or a slice of values"),
    };
    const func_type_info = @typeInfo(@TypeOf(func));
    if (func_type_info != .Fn or func_type_info.Fn.params.len != 1 or func_type_info.Fn.params[0].type.? != T) {
        @compileError("func must be a function that takes a value of type " ++ @typeName(T));
    }
    // `U` is the type of the values returned by the function.
    const U: type = func_type_info.Fn.return_type.?;
    var result: [values.len]U = undefined;
    for (values, 0..) |value, index| {
        result[index] = func(value);
    }
    return result;
}
