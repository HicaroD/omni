package main

use "pkg::..::rope"
use "std::lists"
use "std::io"
use "vendor::platform"

fn check(ok bool) {
    if ok == false {
        fail() @fail
    }
}

fn fail() error {
    return error("rope assertion failed")
}

fn main() i32 {
    platform::locale()
    r := zero<rope::Rope>()
    defer rope::free(&r)
    data u8[5] := .{97, 10, 98, 10, 99}
    rope::replace(&r, 0, 0, data[:]) @fail
    check(rope::size(r.root) == 5)
    check(rope::breaks(r.root) == 2)
    check(rope::line_start(&r, 2) == 4)
    check(rope::line_at(&r, 4) == 2)
    extra u8[2] := .{120, 121}
    rope::replace(&r, 1, 4, extra[:]) @fail
    check(rope::size(r.root) == 4)
    check(rope::byte(&r, 1) == 120)
    check(rope::byte(&r, 3) == 99)
    check(rope::breaks(r.root) == 0)
    all := rope::copy(&r, 0, 4) @fail
    defer lists::free<u8>(&all)
    check(lists::count<u8>(&all) == 4)
    io::println("rope tests passed")
    randomized() @fail
    return 0
}
