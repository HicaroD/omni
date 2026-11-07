package main

use "pkg::editor"
use "std::testing"

test "Dot repeats character deletion at the current cursor with independent undo" {
    testing::assert(repeat_character_delete() == nil)
}

fn repeat_character_delete() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "é世界 abc") @try
    press(&app, "xl.") @try
    assert_editor_text(&app, "世 abc") @try
    press(&app, "u") @try
    assert_editor_text(&app, "世界 abc") @try
    press(&app, "u") @try
    assert_editor_text(&app, "é世界 abc") @try
    editor::key(&app, editor::KeyCtrlR) @try
    return assert_editor_text(&app, "世界 abc")
}

test "Dot repeats a counted word delete as a motion rather than a saved byte range" {
    testing::assert(repeat_word_delete() == nil)
}

fn repeat_word_delete() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a bb 世界 longer last") @try
    press(&app, "d2w.") @try
    assert_editor_text(&app, "last") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "世界 longer last")
}

test "Dot repeats word objects using the word under the new cursor" {
    testing::assert(repeat_delete_case("one longer last", "diww.", "  last") == nil)
}

test "Dot remembers the resolved find target even after a different character find" {
    testing::assert(repeat_delete_case("a世b世c!d世tail", "df世f!0.", "c!d世tail") == nil)
}

test "Dot repeats an Insert session and its backspaces as one undoable edit" {
    testing::assert(repeat_insert_session() == nil)
}

fn repeat_insert_session() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo") @try
    press(&app, "I世x") @try
    editor::key(&app, editor::KeyBackspace) @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "j.") @try
    assert_editor_text(&app, "世one\n世two") @try
    testing::assert(app.mode == editor::Mode::Normal)
    press(&app, "u") @try
    return assert_editor_text(&app, "世one\ntwo")
}

test "Dot repeats a change motion and replacement text in one undo group" {
    testing::assert(repeat_change_words() == nil)
}

fn repeat_change_words() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two longer words tail") @try
    press(&app, "c2wnew") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "w.") @try
    assert_editor_text(&app, "new new tail") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "new longer words tail")
}

test "Dot repeats counted substitution without splitting UTF-8 or losing the replacement" {
    testing::assert(repeat_substitution() == nil)
}

fn repeat_substitution() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "é世 abcdef") @try
    press(&app, "2s!") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "w.") @try
    assert_editor_text(&app, "! !cdef") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "! abcdef")
}

test "Dot repeats linewise paste using the current register rather than a frozen copy" {
    testing::assert(repeat_paste() == nil)
}

fn repeat_paste() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "first\nsecond\nthird") @try
    press(&app, "yypGyy.") @try
    assert_editor_text(&app, "first\nfirst\nsecond\nthird\nthird") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "first\nfirst\nsecond\nthird")
}

test "A count on dot replaces the multiplied operator count and is remembered by later dots" {
    testing::assert(repeat_count_override() == nil)
}

fn repeat_count_override() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a b c d e f g h i j k l m n") @try
    press(&app, "2d2w3.") @try
    assert_editor_text(&app, "h i j k l m n") @try
    press(&app, ".") @try
    assert_editor_text(&app, "k l m n") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "h i j k l m n")
}

test "Counted dot repeats character deletes as one undoable change" {
    testing::assert(repeat_counted_characters() == nil)
}

fn repeat_counted_characters() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "aé世界z") @try
    press(&app, "x3.") @try
    assert_editor_text(&app, "z") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "é世界z")
}

test "Arrow cancellation of an operator find cannot contaminate the next repeatable edit" {
    testing::assert(repeat_after_cancelled_find() == nil)
}

fn repeat_after_cancelled_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo\nthree\nfour") @try
    press(&app, "df") @try
    editor::arrow(&app, editor::AnsiArrowRight) @try
    press(&app, "x.") @try
    return assert_editor_text(&app, "o\ntwo\nthree\nfour")
}

test "Dot replays Insert arrows as movement rather than silently dropping them" {
    testing::assert(repeat_insert_arrows() == nil)
}

fn repeat_insert_arrows() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "ab\ncd") @try
    press(&app, "iX") @try
    editor::arrow(&app, editor::AnsiArrowRight) @try
    press(&app, "Y") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "j0.") @try
    assert_editor_text(&app, "XaYb\nXcYd") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "XaYb\ncd")
}

test "Navigation yanks undo redo and cancelled or unsuccessful edits preserve the last change" {
    testing::assert(repeat_preserves_last_change() == nil)
}

fn repeat_preserves_last_change() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc\n\ndef") @try
    press(&app, ".xuyy") @try
    editor::key(&app, editor::KeyCtrlR) @try
    press(&app, "jxdfZ") @try
    press(&app, "d") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "i") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "j0.") @try
    return assert_editor_text(&app, "bc\n\nef")
}

test "Dot replays resolved mapping keys without applying Normal or Insert mappings again" {
    testing::assert(repeat_mapping_boundary() == nil)
}

fn repeat_mapping_boundary() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo") @try
    editor::configure(&app, "[keys.normal]\nQ = 'Iabc<Esc>'\nI = 'x'\n[keys.insert]\na = 'z'\n") @try
    press(&app, "Qj0.") @try
    return assert_editor_text(&app, "abcone\nabctwo")
}

test "Repeated failed change finds do not replay their replacement as Normal commands" {
    testing::assert(repeat_failed_change_find() == nil)
}

fn repeat_failed_change_find() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a!b\nlast") @try
    press(&app, "cf!xdd") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "j0.") @try
    testing::assert(app.mode == editor::Mode::Normal)
    return assert_editor_text(&app, "xddb\nlast")
}

test "Dot recomputes open-line indentation and counted repeats undo together" {
    testing::assert(repeat_open_line() == nil)
}

fn repeat_open_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "  one\n\ttwo") @try
    press(&app, "o!") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "j2.") @try
    assert_editor_text(&app, "  one\n  !\n\ttwo\n\t!\n\t!") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "  one\n  !\n\ttwo")
}

test "Dot repeats vertical deletes as motions from the new line" {
    testing::assert(repeat_delete_case("a\nb\nc\nd\ne", "dj.", "e") == nil)
}

test "Dot retains the resolved direction and target of operator find repeats" {
    testing::assert(repeat_delete_case("a!b!c!d?tail", "f!0d;f?0.", "c!d?tail") == nil)
}

test "Dot repeats line-end changes and word-object changes with replacement text" {
    testing::assert(repeat_change_case("one\ntwo", "C!", "j0.", "!\n!") == nil)
    testing::assert(repeat_change_case("one longer", "ciw!", "w.", "! !") == nil)
    testing::assert(repeat_change_case("one\ntwo", "cc!", "j0.", "!\n!") == nil)
    testing::assert(repeat_change_case("one\n", "C!", "j.", "!\n!") == nil)
}

fn repeat_change_case(original string, change string, repeat string, expected string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, original) @try
    press(&app, change) @try
    editor::key(&app, editor::KeyCtrlC) @try
    press(&app, repeat) @try
    testing::assert(app.mode == editor::Mode::Normal)
    return assert_editor_text(&app, expected)
}

test "An Insert mapping that undoes the session cannot leave stale text in dot repeat" {
    testing::assert(repeat_insert_action_boundary() == nil)
}

fn repeat_insert_action_boundary() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc") @try
    editor::configure(&app, "[keys.insert]\nZ = 'action:undo'\n") @try
    press(&app, "xi!Z") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, ".") @try
    return assert_editor_text(&app, "c")
}

test "Dot repeats the size of a Visual character edit at the current cursor" {
    testing::assert(repeat_delete_case("é世界 abcdef", "vldw.", "界 cdef") == nil)
}

test "Dot repeats a multiline Visual character shape rather than its total character count" {
    testing::assert(repeat_delete_case("ab\ncdef\nx\nlonger\nlast", "vjdj0.", "def\nonger\nlast") == nil)
}

test "Dot repeats the selected number of Visual lines and undoes it together" {
    testing::assert(repeat_visual_lines() == nil)
}

fn repeat_visual_lines() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a\nb\ncc\nddd\nlast") @try
    press(&app, "Vjd.") @try
    assert_editor_text(&app, "last") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "cc\nddd\nlast")
}

test "Dot repeats a Visual rectangle at the new display column" {
    testing::assert(repeat_visual_block_delete() == nil)
}

fn repeat_visual_block_delete() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcdef\nefghijkl\n世界xy\n123456") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "ljdj0ll.") @try
    assert_editor_text(&app, "cdef\nghkl\n世xy\n123456") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "cdef\nghijkl\n世界xy\n123456")
}

test "Counted dot repeats a Visual shape as one undoable operation" {
    testing::assert(repeat_counted_visual() == nil)
}

fn repeat_counted_visual() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcdefgh") @try
    press(&app, "vld2.") @try
    assert_editor_text(&app, "gh") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "cdefgh")
}

test "Dot repeats Visual changes and their replacement text" {
    testing::assert(repeat_change_case("one two", "vllc!", "w.", "! !") == nil)
    testing::assert(repeat_change_case("a\nbb\nccc\ndddd\nlast", "Vjc!", "j0.", "!\n!\nlast") == nil)
}

test "Dot repeats block Insert replication and undoes all destination rows together" {
    testing::assert(repeat_block_insert() == nil)
}

fn repeat_block_insert() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "ab\ncd\nef\ngh") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "jI!") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "jj0.") @try
    assert_editor_text(&app, "!ab\n!cd\n!ef\n!gh") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "!ab\n!cd\nef\ngh")
}

test "Dot repeats block change deletion and replacement as a single edit" {
    testing::assert(repeat_block_change() == nil)
}

fn repeat_block_change() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nijkl\nmnop") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "ljc!") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "jj0.") @try
    assert_editor_text(&app, "!cd\n!gh\n!kl\n!op") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "!cd\n!gh\nijkl\nmnop")
}

test "Dot repeats block end-of-line append using each destination row's own end" {
    testing::assert(repeat_block_append() == nil)
}

fn repeat_block_append() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a\nlong\nx\nyyy") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "j$A!") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, "jj0.") @try
    return assert_editor_text(&app, "a!\nlong!\nx!\nyyy!")
}

test "Dot repeats Visual paste while P keeps the current register intact" {
    testing::assert(repeat_delete_case("X abcd efgh", "ylwvlPw.", "X Xcd Xgh") == nil)
}

fn repeat_delete_case(original string, keys string, expected string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, original) @try
    press(&app, keys) @try
    return assert_editor_text(&app, expected)
}
