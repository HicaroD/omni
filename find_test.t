package main

use "pkg::editor"
use "pkg::rope"
use "std::lists"
use "std::testing"

test "f finds the counted occurrence after the cursor on the current line" {
    testing::assert(find_forward_character() == nil)
}

fn find_forward_character() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)\nother") @try
    press(&app, "f)") @try
    testing::assert_eq(app.active.cursor, 3)
    press(&app, "02f(") @try
    testing::assert_eq(app.active.cursor, 5)
    return assert_editor_text(&app, "a(b)c(d)\nother")
}

test "F searches backward and excludes the character under the cursor" {
    testing::assert(find_backward_character() == nil)
}

fn find_backward_character() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)") @try
    press(&app, "$F(") @try
    testing::assert_eq(app.active.cursor, 5)
    press(&app, "F(") @try
    testing::assert_eq(app.active.cursor, 1)
    press(&app, "$2F(") @try
    testing::assert_eq(app.active.cursor, 1)
    return nil
}

test "t stops before the counted target rather than on it" {
    testing::assert(till_forward_character() == nil)
}

fn till_forward_character() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)") @try
    press(&app, "t)") @try
    testing::assert_eq(app.active.cursor, 2)
    press(&app, "02t)") @try
    testing::assert_eq(app.active.cursor, 6)
    return nil
}

test "T stops after a target found backward" {
    testing::assert(till_backward_character() == nil)
}

fn till_backward_character() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)") @try
    press(&app, "$T(") @try
    testing::assert_eq(app.active.cursor, 6)
    press(&app, "$2T(") @try
    testing::assert_eq(app.active.cursor, 2)
    return nil
}

test "Character find waits for a complete UTF-8 target and stops on character boundaries" {
    testing::assert(find_unicode_character() == nil)
}

fn find_unicode_character() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "aé界x界!") @try
    press(&app, "f") @try
    editor::key(&app, 231) @try
    testing::assert_eq(app.active.cursor, 0)
    editor::key(&app, 149) @try
    testing::assert_eq(app.active.cursor, 0)
    editor::key(&app, 140) @try
    testing::assert_eq(app.active.cursor, 3)
    press(&app, "f界") @try
    testing::assert_eq(app.active.cursor, 7)
    press(&app, "Fé") @try
    testing::assert_eq(app.active.cursor, 1)
    press(&app, "0t界") @try
    testing::assert_eq(app.active.cursor, 1)
    press(&app, "$T界") @try
    testing::assert_eq(app.active.cursor, 10)
    return nil
}

test "Semicolon repeats the last find with a fresh count and comma reverses it without changing history" {
    testing::assert(repeat_character_find() == nil)
}

fn repeat_character_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)e(f)g") @try
    press(&app, ";,") @try
    testing::assert_eq(app.active.cursor, 0)
    press(&app, "f(2;") @try
    testing::assert_eq(app.active.cursor, 9)
    press(&app, ",") @try
    testing::assert_eq(app.active.cursor, 5)
    press(&app, ";") @try
    testing::assert_eq(app.active.cursor, 9)
    press(&app, "0;") @try
    testing::assert_eq(app.active.cursor, 1)
    return nil
}

test "Repeating a till motion skips the adjacent target that would leave the cursor unchanged" {
    testing::assert(repeat_till_character() == nil)
}

fn repeat_till_character() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "ab,cd,ef,") @try
    press(&app, "t,;") @try
    testing::assert_eq(app.active.cursor, 4)
    press(&app, ",") @try
    testing::assert_eq(app.active.cursor, 3)
    press(&app, ";") @try
    testing::assert_eq(app.active.cursor, 4)
    press(&app, "0f,2;T,;") @try
    testing::assert_eq(app.active.cursor, 3)
    return nil
}

test "Delete character-find ranges include forward targets but exclude the backward starting character" {
    testing::assert(character_find_edit("a(b)c(d)!", "df)", "c(d)!") == nil)
    testing::assert(character_find_edit("a(b)c(d)!", "dt)", ")c(d)!") == nil)
    testing::assert(character_find_edit("a(b)c(d)!", "f!dF(", "a(b)c!") == nil)
    testing::assert(character_find_edit("a(b)c(d)!", "f!dT(", "a(b)c(!") == nil)
}

test "Operators can repeat a find in either direction without making later repeats edit text" {
    testing::assert(character_find_edit("a(b)c(d)!", "f)d;", "a(b!") == nil)
    testing::assert(character_find_edit("a(b)c(d)!", "2f)d,", "a(b)!") == nil)
    testing::assert(find_after_operator_is_motion() == nil)
}

fn find_after_operator_is_motion() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)e(f)") @try
    press(&app, "df);") @try
    testing::assert_eq(app.active.cursor, 3)
    return assert_editor_text(&app, "c(d)e(f)")
}

test "Character finds extend Visual selections including rectangular columns" {
    testing::assert(character_find_edit("a(b)c(d)!", "vf)d", "c(d)!") == nil)
    testing::assert(block_character_find() == nil)
}

fn block_character_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abXcd\nabYcd") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "jfYd") @try
    assert_editor_text(&app, "cd\ncd") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "abXcd\nabYcd")
}

test "Arrow input cancels an unfinished character find before the next command" {
    testing::assert(arrow_cancels_character_find() == nil)
}

fn arrow_cancels_character_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abxc") @try
    press(&app, "df") @try
    input u8[4] := .{27,91,67,120}
    lists::append_slice<u8>(&app.input, input[:]) @try
    editor::decode(&app, false) @try
    return assert_editor_text(&app, "axc")
}

test "Finding a question mark does not match an invalid byte rendered as a placeholder" {
    testing::assert(find_real_question_mark() == nil)
}

fn find_real_question_mark() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a?") @try
    invalid u8[1] := .{255}
    rope::replace(&editor::buffer(&app).text, 1, 1, invalid[:]) @try
    press(&app, "f?") @try
    testing::assert_eq(app.active.cursor, 2)
    return nil
}

test "Backspace cancels a pending target without replacing the last completed find" {
    testing::assert(backspace_cancels_character_find() == nil)
}

fn backspace_cancels_character_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)") @try
    press(&app, "f)df") @try
    editor::key(&app, editor::KeyDelete) @try
    press(&app, ";") @try
    testing::assert_eq(app.active.cursor, 7)
    return assert_editor_text(&app, "a(b)c(d)")
}

test "Counted find changes replace the complete UTF-8 range as one undo unit" {
    testing::assert(change_through_unicode_target() == nil)
}

fn change_through_unicode_target() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a界b界c界d界end\nnext") @try
    press(&app, "2c2f界NEW") @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, editor::KeyEscape) @try
    assert_editor_text(&app, "NEWend\nnext") @try
    press(&app, "u") @try
    assert_editor_text(&app, "a界b界c界d界end\nnext") @try
    editor::key(&app, editor::KeyCtrlR) @try
    return assert_editor_text(&app, "NEWend\nnext")
}

test "Yank composes with character find and makes its range available to paste" {
    testing::assert(character_find_edit("a(b)c(d)!", "yf)p", "aa(b)(b)c(d)!") == nil)
}

test "Unsuccessful finds are atomic and never cross a newline even with huge counts" {
    testing::assert(failed_character_find() == nil)
}

fn failed_character_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)\nx..x") @try
    press(&app, "2f)") @try
    testing::assert_eq(app.active.cursor, 0)
    press(&app, "999999999999999999999999999999999999dF(") @try
    assert_editor_text(&app, "a(b)\nx..x") @try
    press(&app, "dfx") @try
    testing::assert(app.mode == editor::Mode::Normal)
    testing::assert_eq(app.active.cursor, 0)
    press(&app, "j;") @try
    testing::assert_eq(app.active.cursor, 8)
    return assert_editor_text(&app, "a(b)\nx..x")
}

test "Find targets may be command keys, digits, tabs or four-byte characters" {
    testing::assert(find_special_targets() == nil)
}

fn find_special_targets() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "av3\t🙂!") @try
    press(&app, "fv") @try
    testing::assert(app.mode == editor::Mode::Normal)
    testing::assert_eq(app.active.cursor, 1)
    press(&app, "f3") @try
    testing::assert_eq(app.active.cursor, 2)
    press(&app, "f\t") @try
    testing::assert_eq(app.active.cursor, 3)
    press(&app, "f🙂") @try
    testing::assert_eq(app.active.cursor, 4)
    return nil
}

test "Escape and malformed UTF-8 cancel targets without editing or replacing find history" {
    testing::assert(cancel_invalid_character_find() == nil)
}

fn cancel_invalid_character_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)e(f)g(h)") @try
    press(&app, "f)df") @try
    editor::key(&app, 231) @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, ";df") @try
    // An overlong encoding must not become a real target.
    editor::key(&app, 224) @try
    editor::key(&app, 128) @try
    editor::key(&app, 128) @try
    press(&app, ";df") @try
    // Surrogates are not Unicode scalar values.
    editor::key(&app, 237) @try
    editor::key(&app, 160) @try
    editor::key(&app, 128) @try
    press(&app, ";") @try
    testing::assert_eq(app.active.cursor, 15)
    return assert_editor_text(&app, "a(b)c(d)e(f)g(h)")
}

fn character_find_edit(original string, keys string, expected string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, original) @try
    press(&app, keys) @try
    assert_editor_text(&app, expected) @try
    press(&app, "u") @try
    assert_editor_text(&app, original) @try
    editor::key(&app, editor::KeyCtrlR) @try
    return assert_editor_text(&app, expected)
}
