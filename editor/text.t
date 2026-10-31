package editor

use "std::lists"
use "std::strings"
use "vendor::platform"
use "std::memory"

fn canonical(path string) (strings::Owned, error) {
    if path == "" {
        return strings::clone("")
    }
    c := strings::to_c(path) @try
    defer strings::free_c(&c)
    resolved rawptr := nil
    if platform::path(strings::c_view(&c), &resolved) != 0 {
        return zero<strings::Owned>(), error("cannot resolve file path")
    }
    defer memory::free(resolved)
    return strings::clone(strings::from_c(platform::cview(resolved)))
}

fn append_text(out *lists::List<u8>, text string) error {
    c := strings::to_c(text) @try
    defer strings::free_c(&c)
    i u64 := 0
    while i < strings::len(text) {
        lists::append<u8>(out, platform::byte(strings::c_view(&c), i)) @try
        i = i + 1
    }
    return nil
}

fn text_bytes(text string) (lists::List<u8>, error) {
    out := lists::create<u8>()
    defer lists::free<u8>(&out)
    append_text(&out, text) @try
    return memory::take<lists::List<u8>>(&out), nil
}

fn owned_bytes(bytes u8[]) (strings::Owned, error) {
    temp := lists::create<u8>()
    defer lists::free<u8>(&temp)
    lists::append_slice<u8>(&temp, bytes) @try
    lists::append<u8>(&temp, 0) @try
    return strings::clone(strings::from_c(platform::cview(slice_data<u8>(lists::view<u8>(&temp)))))
}

fn number(out *lists::List<u8>, value u64) error {
    digits u8[10] := .{48,49,50,51,52,53,54,55,56,57}
    if value >= 10 {
        number(out, value / 10) @try
    }
    return lists::append<u8>(out, digits[value - (value / 10) * 10])
}

fn min(a u64, b u64) u64 {
    if a < b {
        return a
    }
    return b
}
