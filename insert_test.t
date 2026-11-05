package main

use "pkg::editor"
use "std::testing"

test "I inserts before the first nonblank character and undoes independently" {
    testing::assert(insert_first_nonblank() == nil)
}

fn insert_first_nonblank() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, " \t  世界 next\nlast") @try
    press(&app, "$I!") @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, 27) @try
    assert_editor_text(&app, " \t  !世界 next\nlast") @try
    press(&app, "u") @try
    return assert_editor_text(&app, " \t  世界 next\nlast")
}

test "A appends at the current line end without changing the next line" {
    testing::assert(append_line_end() == nil)
}

fn append_line_end() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "世界\nnext") @try
    press(&app, "A!") @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, 27) @try
    assert_editor_text(&app, "世界!\nnext") @try
    press(&app, "u") @try
    assert_editor_text(&app, "世界\nnext") @try
    editor::key(&app, editor::KeyCtrlR) @try
    return assert_editor_text(&app, "世界!\nnext")
}

test "O opens above the current line with its mixed indentation and undoes together" {
    testing::assert(open_line_above() == nil)
}

fn open_line_above() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "first\n \t  世界\nlast") @try
    press(&app, "j$O!") @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, 27) @try
    assert_editor_text(&app, "first\n \t  !\n \t  世界\nlast") @try
    press(&app, "u") @try
    assert_editor_text(&app, "first\n \t  世界\nlast") @try
    editor::key(&app, editor::KeyCtrlR) @try
    return assert_editor_text(&app, "first\n \t  !\n \t  世界\nlast")
}

test "Counted s substitutes whole UTF-8 characters and undoes replacement together" {
    testing::assert(substitute_characters() == nil)
}

fn substitute_characters() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "é世界 tail\nnext") @try
    press(&app, "2s!") @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, 27) @try
    assert_editor_text(&app, "!界 tail\nnext") @try
    press(&app, "u") @try
    assert_editor_text(&app, "é世界 tail\nnext") @try
    editor::key(&app, editor::KeyCtrlR) @try
    return assert_editor_text(&app, "!界 tail\nnext")
}

test "C changes from the cursor to line end and keeps the next line separate" {
    testing::assert(change_line_tail() == nil)
}

fn change_line_tail() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "世界 tail\nnext") @try
    press(&app, "lC!") @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, 27) @try
    assert_editor_text(&app, "世!\nnext") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "世界 tail\nnext")
}

test "s and C on an empty line enter Insert mode without erasing the previous yank" {
    testing::assert(change_empty_preserves_yank("s") == nil)
    testing::assert(change_empty_preserves_yank("C") == nil)
}

fn change_empty_preserves_yank(command string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "keep\n\nnext") @try
    press(&app, "yyj") @try
    press(&app, command) @try
    testing::assert(app.mode == editor::Mode::Insert)
    press(&app, "!") @try
    editor::key(&app, 27) @try
    press(&app, "p") @try
    return assert_editor_text(&app, "keep\n!\nkeep\nnext")
}

test "I and A handle empty, whitespace-only and unterminated lines" {
    testing::assert(insert_command_case("", "I!", "!") == nil)
    testing::assert(insert_command_case("", "A!", "!") == nil)
    testing::assert(insert_command_case(" \t \nnext", "I!", " \t !\nnext") == nil)
    testing::assert(insert_command_case(" \t \nnext", "A!", " \t !\nnext") == nil)
    testing::assert(insert_command_case("世界", "I!", "!世界") == nil)
    testing::assert(insert_command_case("世界", "A!", "世界!") == nil)
}

test "O preserves line boundaries above the first line and at a final empty line" {
    testing::assert(insert_command_case("  first\nnext", "O!", "  !\n  first\nnext") == nil)
    testing::assert(insert_command_case("", "O!", "!\n") == nil)
    testing::assert(insert_command_case("first\n", "GO!", "first\n!\n") == nil)
}

test "Huge s counts stop at line end without deleting its newline" {
    testing::assert(insert_command_case("é世\nnext", "999999999999999999999999999999999999999s!", "!\nnext") == nil)
    testing::assert(insert_command_case("", "s!", "!") == nil)
}

test "C accepts line counts and clamps oversized counts at EOF" {
    testing::assert(insert_command_case("ab\ncd\nef", "l2C!", "a!\nef") == nil)
    testing::assert(insert_command_case("ab\ncd\nef", "l999999999999999999999999999999999999999C!", "a!") == nil)
    testing::assert(insert_command_case("", "C!", "!") == nil)
}

fn insert_command_case(original string, keys string, expected string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, original) @try
    press(&app, keys) @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, 27) @try
    assert_editor_text(&app, expected) @try
    press(&app, "u") @try
    assert_editor_text(&app, original) @try
    editor::key(&app, editor::KeyCtrlR) @try
    return assert_editor_text(&app, expected)
}
