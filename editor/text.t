package editor

use "std::lists"
use "std::strings"
use "std::path"
use "std::memory"

fn canonical(name string) (strings::Owned, error) {
    if name == "" {
        return strings::clone("")
    }
    return path::canonicalize_for_create(name)
}

fn append_text(out *lists::List<u8>, text string) error {
    i u64 := 0
    while i < strings::len(text) {
        byte := strings::byte_at(text, i) @try
        lists::append<u8>(out, byte) @try
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
    return strings::from_bytes(bytes)
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
