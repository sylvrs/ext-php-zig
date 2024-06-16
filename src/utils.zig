/// `map` is a function that takes a return type, an array of values, and a function that takes a value and returns a value of the return type.
/// The function passed can either take one parameter (the value) or two parameters (the value and the index).
pub fn map(comptime values: anytype, comptime func: anytype) [values.len](@typeInfo(@TypeOf(func)).Fn.return_type.?) {
    // `T` is the type of the values in the array.
    const T: type = switch (@typeInfo(@TypeOf(values))) {
        .Array => |array| array.child,
        .Pointer => |ptr| ptr.child,
        inline else => @compileError("map function must take an array or a slice of values"),
    };
    const func_type_info = @typeInfo(@TypeOf(func));
    if (func_type_info != .Fn) {
        @compileError("func must be a function");
    }
    // `U` is the type of the values returned by the function.
    const U: type = func_type_info.Fn.return_type.?;
    const params = func_type_info.Fn.params;
    if (params.len != 1 and params.len != 2) {
        @compileError("func must take one or two parameters");
    } else if (params[0].type.? != T) {
        @compileError("func's parameter must be of type " ++ @typeName(T));
    } else if (params.len == 2 and params[1].type.? != usize) {
        @compileError("func's second parameter (the index) must be of type usize");
    }
    var result: [values.len]U = undefined;
    inline for (values, 0..) |value, index| {
        result[index] = @call(
            .auto,
            func,
            if (params.len == 2) .{ value, index } else .{value},
        );
    }
    return result;
}
