const builtin = @import("builtin");

pub usingnamespace @cImport({
    if (builtin.os.tag == .windows) {
        @cDefine("WINDOWS", "1");
        @cDefine("ZEND_WIN32", "1");
        @cDefine("PHP_WIN32", "1");
        // TODO!: in order to get some of the linker symbols resolved on Windows,
        // we'll have to work around PHP's macro definitions (specifically, __clang__)
        // Otherwise, many things that use custom calling conventions will fail to link.
        if (builtin.cpu.arch == .x86) {
            @cDefine("WIN32", "1");
            @cUndef("__clang__");
            @cInclude("zend_portability.h");
            @cDefine("__clang__", "");
        }
    }
    @cInclude("php.h");
    @cInclude("ext/standard/info.h");
    // Zend imports
    @cInclude("zend_API.h");
    @cInclude("zend_exceptions.h");
    @cInclude("zend_type_info.h");
});
