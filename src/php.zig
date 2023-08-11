/// `internal` exposes PHP's internal functions and structs.
pub const internal = @import("internal.zig");
/// `zend` contains the definitions of the Zend's structs and functions.
pub const zend = @import("zend.zig");
/// `utils` contains various utility functions that are used throughout the library but could be useful to the users as well.
pub const utils = @import("utils.zig");
/// `Module` represents the library's wrapper around the Zend's ModuleEntry struct.
pub const Module = @import("Module.zig");
