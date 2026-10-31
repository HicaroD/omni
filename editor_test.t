package main

use "pkg::editor"
use "pkg::rope"
use "std::lists"
use "std::memory"
use "std::strings"
use "std::testing"

fn setup_editor(app *editor::App, text string) error {
    app.root = editor::new_pane() @try
    app.active = app.root
    editor::open_buffer(app, "") @try
    bytes := editor::text_bytes(text) @try
    defer lists::free<u8>(&bytes)
    rope::replace(&editor::buffer(app).text, 0, 0, lists::view<u8>(&bytes)) @try
    return nil
}

fn assert_editor_text(app *editor::App, expected string) error {
    b := editor::buffer(app)
    bytes := rope::copy(&b.text, 0, rope::size(b.text.root)) @try
    defer lists::free<u8>(&bytes)
    text := editor::owned_bytes(lists::view<u8>(&bytes)) @try
    defer strings::free(&text)
    testing::assert_eq(strings::view(&text), expected)
    return nil
}

test "o copies mixed indentation and places typed text after it" {
    testing::assert(open_indented_line() == nil)
}

fn open_indented_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, " \t  first\nnext") @try
    editor::key(&app, 111) @try
    testing::assert_eq(app.mode, 1)
    testing::assert_eq(app.active.cursor, 14)
    editor::key(&app, 88) @try
    assert_editor_text(&app, " \t  first\n \t  X\nnext") @try
    editor::key(&app, 27) @try
    editor::key(&app, 117) @try
    assert_editor_text(&app, " \t  first\nnext") @try
    editor::key(&app, 18) @try
    assert_editor_text(&app, " \t  first\n \t  X\nnext") @try
    return nil
}

test "insert Enter preserves indentation while splitting a line" {
    testing::assert(enter_indented_line() == nil)
}

fn enter_indented_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "  first second") @try
    app.active.cursor = 8
    editor::key(&app, 105) @try
    editor::key(&app, 13) @try
    testing::assert_eq(app.active.cursor, 11)
    editor::key(&app, 88) @try
    assert_editor_text(&app, "  first \n  Xsecond") @try
    editor::key(&app, 27) @try
    editor::key(&app, 117) @try
    assert_editor_text(&app, "  first second") @try
    return nil
}

test "o preserves indentation at EOF and leaves unindented lines unindented" {
    testing::assert(open_line_boundary("  last", "  last\n  ", 9) == nil)
    testing::assert(open_line_boundary("\t ", "\t \n\t ", 5) == nil)
    testing::assert(open_line_boundary("plain", "plain\n", 6) == nil)
    testing::assert(open_line_boundary("", "\n", 1) == nil)
}

fn open_line_boundary(text string, expected string, cursor u64) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, text) @try
    editor::key(&app, 111) @try
    testing::assert_eq(app.active.cursor, cursor)
    return assert_editor_text(&app, expected)
}

test "insert newline inside indentation copies only the prefix before the cursor" {
    testing::assert(split_indentation() == nil)
}

fn split_indentation() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "    text") @try
    app.active.cursor = 2
    editor::key(&app, 105) @try
    editor::key(&app, 10) @try
    testing::assert_eq(app.active.cursor, 5)
    return assert_editor_text(&app, "  \n    text")
}

test "dollar moves to the current line end without crossing the newline" {
    testing::assert(dollar_motion() == nil)
}

fn dollar_motion() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two\n\nlast") @try
    editor::key(&app, 119) @try
    editor::key(&app, 36) @try
    testing::assert_eq(app.active.cursor, 7)
    editor::key(&app, 106) @try
    editor::key(&app, 36) @try
    testing::assert_eq(app.active.cursor, 8)
    editor::key(&app, 106) @try
    editor::key(&app, 36) @try
    testing::assert_eq(app.active.cursor, 13)
    return nil
}

test "normal w is safe in empty buffers and at a multibyte final character" {
    testing::assert(word_boundaries() == nil)
}

fn word_boundaries() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "") @try
    editor::key(&app, 119) @try
    testing::assert_eq(app.active.cursor, 0)
    bytes := editor::text_bytes("  é") @try
    defer lists::free<u8>(&bytes)
    rope::replace(&editor::buffer(&app).text, 0, 0, lists::view<u8>(&bytes)) @try
    editor::key(&app, 119) @try
    testing::assert_eq(app.active.cursor, 2)
    editor::key(&app, 119) @try
    testing::assert_eq(app.active.cursor, 2)
    app.active.cursor = 4
    editor::key(&app, 119) @try
    testing::assert_eq(app.active.cursor, 4)
    return nil
}

test "normal w moves to the next word without changing text" {
    testing::assert(word_motion() == nil)
}

fn word_motion() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one  two_three 42") @try
    editor::key(&app, 119) @try
    testing::assert_eq(app.active.cursor, 5)
    editor::key(&app, 119) @try
    testing::assert_eq(app.active.cursor, 15)
    testing::assert_eq(app.mode, 0)
    testing::assert_eq(editor::buffer(&app).revision, 0)
    return nil
}

test "normal w separates punctuation from keyword runs and preserves UTF-8" {
    testing::assert(word_punctuation() == nil)
}

fn word_punctuation() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "café_name42...next\tend") @try
    expected u64[4] := .{12,15,20,22}
    for at in expected {
        editor::key(&app, 119) @try
        testing::assert_eq(app.active.cursor, at)
    }
    editor::key(&app, 119) @try
    testing::assert_eq(app.active.cursor, 22)
    return nil
}

test "normal w crosses line indentation but stops on empty lines" {
    testing::assert(word_lines() == nil)
}

fn word_lines() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\n  two\n\n\n  fin") @try
    expected u64[5] := .{6,10,11,14,16}
    for at in expected {
        editor::key(&app, 119) @try
        testing::assert_eq(app.active.cursor, at)
    }
    return nil
}

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
