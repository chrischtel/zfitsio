const std = @import("std");
pub const c = @cImport({
    @cInclude("fitsio.h");
});
