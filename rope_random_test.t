package main

use "pkg::rope"
use "std::lists"
use "std::memory"

fn test_remainder(value u64, divisor u64) u64 {
    return value - (value / divisor) * divisor
}

fn test_random(seed *u64, limit u64) u64 {
    next := *seed * 48271 + 1
    *seed = test_remainder(next, 2147483647)
    return test_remainder(*seed, limit)
}

fn verify_node(n *rope::Node) (u64, u64, u64) {
    if n == nil {
        return 0, 0, 0
    }
    left_bytes, left_lines, left_height := verify_node(n.left)
    right_bytes, right_lines, right_height := verify_node(n.right)
    check(n.used > 0 and n.used <= 512)
    lines u64 := 0
    i u64 := 0
    while i < n.used {
        if n.data[i] == 10 {
            lines = lines + 1
        }
        i = i + 1
    }
    check(lines == n.local_lines)
    check(n.bytes == left_bytes + n.used + right_bytes)
    check(n.lines == left_lines + lines + right_lines)
    if n.left != nil {
        check(n.left.priority >= n.priority)
    }
    if n.right != nil {
        check(n.right.priority >= n.priority)
    }
    height := left_height + 1
    if right_height >= left_height {
        height = right_height + 1
    }
    check(height < 128)
    return n.bytes, n.lines, height
}

fn randomized() error {
    r := zero<rope::Rope>()
    defer rope::free(&r)
    reference := lists::create<u8>()
    defer lists::free<u8>(&reference)
    seed u64 := 73
    values u8[9] := .{0,10,97,98,127,128,195,169,255}
    initial := zero<u8[8192]>()
    i u64 := 0
    while i < 8192 {
        initial[i] = values[test_random(&seed, 9)]
        i = i + 1
    }
    rope::replace(&r, 0, 0, initial[:]) @try
    lists::append_slice<u8>(&reference, initial[:]) @try
    step u64 := 0
    while step < 1800 {
        size := lists::count<u8>(&reference)
        start := test_random(&seed, size + 1)
        removed := test_random(&seed, 65)
        if removed > size - start {
            removed = size - start
        }
        inserted := test_random(&seed, 97)
        data := zero<u8[96]>()
        j u64 := 0
        while j < inserted {
            data[j] = values[test_random(&seed, 9)]
            j = j + 1
        }
        part := data[0:inserted] @try
        rope::replace(&r, start, start + removed, part) @try
        replacement := lists::create<u8>()
        defer lists::free<u8>(&replacement)
        old := lists::view<u8>(&reference)
        prefix := old[0:start] @try
        tail := old[start + removed:size] @try
        lists::append_slice<u8>(&replacement, prefix) @try
        lists::append_slice<u8>(&replacement, part) @try
        lists::append_slice<u8>(&replacement, tail) @try
        lists::free<u8>(&reference)
        reference = memory::take<lists::List<u8>>(&replacement)
        bytes, breaks, depth := verify_node(r.root)
        check(bytes == lists::count<u8>(&reference))
        expected := lists::view<u8>(&reference)
        at := test_random(&seed, len(expected) + 1)
        line u64 := 0
        last_start u64 := 0
        k u64 := 0
        while k < len(expected) {
            check(rope::byte(&r, k) == expected[k])
            if k < at and expected[k] == 10 {
                line = line + 1
                last_start = k + 1
            }
            k = k + 1
        }
        check(rope::line_at(&r, at) == line)
        check(rope::line_start(&r, line) == last_start)
        step = step + 1
    }
    before := rope::size(r.root)
    invalid := rope::replace(&r, before + 1, before + 1, zero<u8[]>())
    check(invalid != nil)
    check(rope::size(r.root) == before)
    flat := rope::copy(&r, 0, before) @try
    defer lists::free<u8>(&flat)
    actual := lists::view<u8>(&flat)
    expected_all := lists::view<u8>(&reference)
    k2 u64 := 0
    while k2 < len(actual) {
        check(actual[k2] == expected_all[k2])
        k2 = k2 + 1
    }
    rope::replace(&r, 0, before, zero<u8[]>()) @try
    check(r.root == nil)
    return nil
}
