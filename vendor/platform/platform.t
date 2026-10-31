package platform

use "std::ffi::c"

@[header="platform.h", default_cc="c"]
extern {
    @[link_name="omni_path"]
    fn path(path c::ConstCString, resolved *rawptr) i32
    @[link_name="omni_stamp"]
    fn stamp(path c::ConstCString) u64
    @[link_name="omni_cview"]
    fn cview(data rawptr) c::ConstCString
    @[link_name="omni_widen"]
    fn widen(value u8) u32
    @[link_name="omni_argc"]
    fn argc() u64
    @[link_name="omni_arg"]
    fn arg(i u64) c::ConstCString
    @[link_name="omni_root"]
    fn root(path c::ConstCString) i32
    @[link_name="omni_load"]
    fn load(path c::ConstCString, data *rawptr, length *u64) i32
    @[link_name="omni_preview"]
    fn preview(path c::ConstCString, data *rawptr, length *u64) i32
    @[link_name="omni_save"]
    fn save(path c::ConstCString, data rawptr, length u64) i32
    @[link_name="omni_width"]
    fn width(codepoint u32) i32
    @[link_name="omni_locale"]
    fn locale()
    @[link_name="omni_byte"]
    fn byte(text c::ConstCString, i u64) u8
    @[link_name="omni_spawn"]
    fn spawn(kind i32, query c::ConstCString, hidden bool, ignored bool, regex bool, process *rawptr) i32
    @[link_name="omni_poll"]
    fn poll(process rawptr, buffer rawptr, capacity u64, count *u64) i32
    @[link_name="omni_cancel"]
    fn cancel(process rawptr)
    @[link_name="omni_copy"]
    fn copy(data rawptr, length u64) i32
    @[link_name="omni_paste"]
    fn paste(data *rawptr, length *u64) i32
}
