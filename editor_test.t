package main

use "pkg::editor"
use "std::lists"
use "std::memory"
use "std::strings"
use "std::testing"

test "fragmented escape and paste prefixes remain buffered" {
    result := escape_prefixes()
    testing::assert(result == nil)
}

fn escape_prefixes() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    lists::append<u8>(&app.input, 27) @try
    editor::decode(&app, false) @try
    testing::assert_eq(lists::count<u8>(&app.input), 1)
    editor::decode(&app, true) @try
    testing::assert_eq(lists::count<u8>(&app.input), 0)

    partial u8[4] := .{27,91,50,48}
    lists::append_slice<u8>(&app.input, partial[:]) @try
    editor::decode(&app, false) @try
    testing::assert_eq(lists::count<u8>(&app.input), 4)
    finish u8[2] := .{48,126}
    lists::append_slice<u8>(&app.input, finish[:]) @try
    editor::decode(&app, false) @try
    testing::assert(app.paste)
    testing::assert_eq(lists::count<u8>(&app.input), 0)

    end u8[6] := .{27,91,50,48,49,126}
    lists::append_slice<u8>(&app.input, end[:]) @try
    editor::decode(&app, false) @try
    testing::assert(app.paste == false)
    return nil
}

test "decimal parsing safely reaches slice and digit-table boundaries" {
    digits u8[3] := .{49,50,51}
    invalid u8[1] := .{58}
    testing::assert_eq(editor::parse_decimal(digits[:], 0, 3), 123)
    testing::assert_eq(editor::parse_decimal(invalid[:], 0, 1), 0)
}

test "fuzzy picker caps results and can select candidates past the cap" {
    result := picker_ranking()
    testing::assert(result == nil)
}

fn add_picker_item(p *editor::Picker, text string) error {
    label := strings::clone(text) @try
    defer strings::free(&label)
    lists::append<editor::Item>(&p.items, editor::Item{label: label}) @try
    memory::take<strings::Owned>(&label)
    return nil
}

fn picker_ranking() error {
    p := zero<editor::Picker>()
    defer editor::close_picker(&p)
    p.kind = 3
    i u64 := 0
    while i < 120 {
        add_picker_item(&p, "file") @try
        i = i + 1
    }
    add_picker_item(&p, "focus") @try
    editor::filter_picker(&p) @try
    testing::assert_eq(lists::count<editor::Match>(&p.matches), 100)
    query u8[3] := .{102,99,115}
    lists::append_slice<u8>(&p.query, query[:]) @try
    editor::filter_picker(&p) @try
    testing::assert_eq(lists::count<editor::Match>(&p.matches), 1)
    matches := lists::view<editor::Match>(&p.matches)
    testing::assert_eq(matches[0].index, 120)
    return nil
}
