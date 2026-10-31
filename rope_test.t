package main

use "pkg::rope"
use "std::lists"
use "std::testing"

fn check(ok bool) {
    testing::assert(ok)
}

test "rope splices preserve bytes and line counts" {
    result := basic_splice()
    testing::assert(result == nil)
}

test "1800 randomized rope edits preserve tree invariants" {
    result := randomized()
    testing::assert(result == nil)
}

fn basic_splice() error {
    r := zero<rope::Rope>()
    defer rope::free(&r)
    data u8[5] := .{97, 10, 98, 10, 99}
    rope::replace(&r, 0, 0, data[:]) @try
    testing::assert_eq(rope::size(r.root), 5)
    testing::assert_eq(rope::breaks(r.root), 2)
    testing::assert_eq(rope::line_start(&r, 2), 4)
    testing::assert_eq(rope::line_at(&r, 4), 2)
    extra u8[2] := .{120, 121}
    rope::replace(&r, 1, 4, extra[:]) @try
    testing::assert_eq(rope::size(r.root), 4)
    testing::assert_eq(rope::byte(&r, 1), 120)
    testing::assert_eq(rope::byte(&r, 3), 99)
    testing::assert_eq(rope::breaks(r.root), 0)
    all := rope::copy(&r, 0, 4) @try
    defer lists::free<u8>(&all)
    testing::assert_eq(lists::count<u8>(&all), 4)
    return nil
}
