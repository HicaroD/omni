package main

use "pkg::editor"
use "std::testing"
use "std::lists"

fn replace_fields(app *editor::App, query string, replacement string) error {
    bytes := editor::text_bytes(query) @try
    defer lists::free<u8>(&bytes)
    for byte in lists::view<u8>(&bytes) {
        editor::key(app, byte) @try
    }
    editor::key(app, 9) @try
    after := editor::text_bytes(replacement) @try
    defer lists::free<u8>(&after)
    for byte in lists::view<u8>(&after) {
        editor::key(app, byte) @try
    }
    return nil
}

test "case-sensitive whole-word replacement excludes longer and Unicode words" {
    testing::assert(replace_words() == nil)
}

fn replace_words() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "foo Foo food _foo fooé éfoo foo") @try
    editor::start_replace(&app, false) @try
    editor::key(&app, 20) @try
    editor::key(&app, 23) @try
    replace_fields(&app, "foo", "bar") @try
    editor::key(&app, 1) @try
    return assert_editor_text(&app, "bar Foo food _foo fooé éfoo bar")
}

test "zero-length regex replacement advances over complete Unicode characters" {
    testing::assert(replace_empty_matches() == nil)
}

fn replace_empty_matches() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "é界\n") @try
    editor::start_replace(&app, false) @try
    editor::key(&app, 18) @try
    replace_fields(&app, "(?=.)", "X") @try
    editor::key(&app, 1) @try
    assert_editor_text(&app, "XéX界\n") @try
    editor::key(&app, 27) @try
    editor::key(&app, 117) @try
    assert_editor_text(&app, "é界\n") @try
    editor::key(&app, 18) @try
    return assert_editor_text(&app, "XéX界\n")
}

test "regex matching never crosses lines even with dotall enabled" {
    testing::assert(replace_line_boundary() == nil)
}

fn replace_line_boundary() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "first\nsecond") @try
    editor::start_replace(&app, false) @try
    editor::key(&app, 18) @try
    replace_fields(&app, "(?s)first.*second", "oops") @try
    editor::key(&app, 1) @try
    return assert_editor_text(&app, "first\nsecond")
}

test "invalid regex and unknown capture replacement cannot edit text" {
    testing::assert(replace_invalid() == nil)
}

fn replace_invalid() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "foo") @try
    editor::start_replace(&app, false) @try
    editor::key(&app, 18) @try
    replace_fields(&app, "(", "bad") @try
    editor::key(&app, 1) @try
    assert_editor_text(&app, "foo") @try
    editor::key(&app, 9) @try
    editor::key(&app, 127) @try
    editor::key(&app, 102) @try
    editor::key(&app, 111) @try
    editor::key(&app, 111) @try
    editor::key(&app, 9) @try
    editor::key(&app, 36) @try
    editor::key(&app, 57) @try
    editor::key(&app, 1) @try
    return assert_editor_text(&app, "foo")
}

test "empty replacement deletes all matches as one undo group" {
    testing::assert(replace_delete() == nil)
}

fn replace_delete() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "foo é foo") @try
    editor::start_replace(&app, false) @try
    replace_fields(&app, "foo", "") @try
    editor::key(&app, 1) @try
    assert_editor_text(&app, " é ") @try
    editor::key(&app, 27) @try
    editor::key(&app, 117) @try
    return assert_editor_text(&app, "foo é foo")
}

test "file selection toggles every match and individual selection can restore one" {
    testing::assert(replace_selection() == nil)
}

fn replace_selection() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "foo foo foo") @try
    editor::start_replace(&app, false) @try
    replace_fields(&app, "foo", "bar") @try
    editor::key(&app, 6) @try
    editor::key(&app, 24) @try
    editor::key(&app, 1) @try
    return assert_editor_text(&app, "bar foo foo")
}

test "replacement adjusts cursors without moving them to the last replacement" {
    testing::assert(replace_cursor() == nil)
}

fn replace_cursor() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "foo tail") @try
    app.active.cursor = 6
    editor::start_replace(&app, false) @try
    replace_fields(&app, "foo", "longer") @try
    editor::key(&app, 1) @try
    testing::assert_eq(app.active.cursor, 9)
    return assert_editor_text(&app, "longer tail")
}

test "whole-word replacement treats Unicode numbers and spacing marks as word parts" {
    testing::assert(replace_unicode_word_parts() == nil)
}

fn replace_unicode_word_parts() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "foo² fooा foo") @try
    editor::start_replace(&app, false) @try
    editor::key(&app, 23) @try
    replace_fields(&app, "foo", "bar") @try
    editor::key(&app, 1) @try
    return assert_editor_text(&app, "foo² fooा bar")
}
