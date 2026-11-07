package main

use "pkg::editor"
use "pkg::rope"
use "std::lists"
use "std::memory"
use "std::strings"
use "std::testing"

test "Normal counts repeat motions and zero still moves to line start" {
    testing::assert(counted_motions() == nil)
}

fn counted_motions() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two three four\nnext\nlast") @try
    press(&app, "3w") @try
    testing::assert_eq(app.active.cursor, 14)
    press(&app, "0") @try
    testing::assert_eq(app.active.cursor, 0)
    press(&app, "2j") @try
    testing::assert_eq(app.active.cursor, 24)
    return assert_editor_text(&app, "one two three four\nnext\nlast")
}

test "Counts before and after a doubled operator multiply and undo together" {
    testing::assert(counted_lines() == nil)
}

fn counted_lines() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo\nthree\nfour\nfive\nsix") @try
    press(&app, "2d2d") @try
    assert_editor_text(&app, "five\nsix") @try
    press(&app, "u") @try
    assert_editor_text(&app, "one\ntwo\nthree\nfour\nfive\nsix") @try
    press(&app, "2yyGp") @try
    return assert_editor_text(&app, "one\ntwo\nthree\nfour\nfive\nsix\none\ntwo")
}

test "Delete composes with counted word motions and yanks the deleted range" {
    testing::assert(delete_words() == nil)
}

fn delete_words() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two three four") @try
    press(&app, "d2w") @try
    assert_editor_text(&app, "three four") @try
    press(&app, "u") @try
    assert_editor_text(&app, "one two three four") @try
    press(&app, "2dw") @try
    assert_editor_text(&app, "three four") @try
    press(&app, "p") @try
    return assert_editor_text(&app, "tone two hree four")
}

test "Word delete preserves the final line break and removes whole UTF-8 characters at EOF" {
    testing::assert(delete_word_boundaries() == nil)
}

fn delete_word_boundaries() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "éclair  \n  世界") @try
    press(&app, "dw") @try
    assert_editor_text(&app, "\n  世界") @try
    press(&app, "j0wdw") @try
    assert_editor_text(&app, "\n  ") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "\n  世界")
}

test "Change word preserves trailing whitespace and replacement undoes as one edit" {
    testing::assert(change_word() == nil)
}

fn change_word() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two three") @try
    press(&app, "c2wnew") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "new three") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "one two three")
}

test "Operators compose with backward, horizontal, line-end and vertical motions" {
    testing::assert(operator_motions() == nil)
}

fn operator_motions() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two\nthree\nfour") @try
    press(&app, "wd0") @try
    assert_editor_text(&app, "two\nthree\nfour") @try
    press(&app, "d$") @try
    assert_editor_text(&app, "\nthree\nfour") @try
    press(&app, "u0dj") @try
    assert_editor_text(&app, "four") @try
    press(&app, "uGdk") @try
    return assert_editor_text(&app, "two")
}

test "Inner word change finds the whole word from its middle and undoes replacement" {
    testing::assert(inner_word_change() == nil)
}

fn inner_word_change() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "hello 世界 next") @try
    press(&app, "wlciwnew") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "hello new next") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "hello 世界 next")
}

test "Around word delete prefers trailing spaces and uses preceding spaces at line end" {
    testing::assert(around_word_delete() == nil)
}

fn around_word_delete() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one  two three") @try
    press(&app, "wdaw") @try
    assert_editor_text(&app, "one  three") @try
    press(&app, "daw") @try
    return assert_editor_text(&app, "one")
}

test "Counts select absolute lines with G and gg and relative lines with dollar" {
    testing::assert(counted_line_targets() == nil)
}

fn counted_line_targets() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a\nbb\nccc\ndddd") @try
    press(&app, "2G") @try
    testing::assert_eq(app.active.cursor, 2)
    press(&app, "3gg") @try
    testing::assert_eq(app.active.cursor, 5)
    press(&app, "gg2$") @try
    testing::assert_eq(app.active.cursor, 4)
    press(&app, "G") @try
    testing::assert_eq(app.active.cursor, 9)
    return nil
}

test "Word text objects honor multiplied counts" {
    testing::assert(counted_word_objects() == nil)
}

fn counted_word_objects() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two three four five") @try
    press(&app, "2d2iw") @try
    assert_editor_text(&app, "three four five") @try
    press(&app, "u2daw") @try
    return assert_editor_text(&app, "three four five")
}

test "Cancelled and invalid commands do not leak their counts into later edits" {
    testing::assert(cancelled_counts() == nil)
}

fn cancelled_counts() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one two three four") @try
    press(&app, "3vvw") @try
    testing::assert_eq(app.active.cursor, 4)
    press(&app, "d2") @try
    editor::key(&app, 27) @try
    press(&app, "dizw") @try
    testing::assert_eq(app.active.cursor, 8)
    press(&app, "0d2iw") @try
    return assert_editor_text(&app, "two three four")
}

test "Around word on whitespace includes the next word without eating its following space" {
    testing::assert(around_whitespace() == nil)
}

fn around_whitespace() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one  two three") @try
    press(&app, "3ldaw") @try
    return assert_editor_text(&app, "one three")
}

test "Counted word operators treat empty lines as word-motion stops" {
    testing::assert(delete_across_empty_lines() == nil)
}

fn delete_across_empty_lines() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\n\n\ntwo") @try
    press(&app, "d2w") @try
    return assert_editor_text(&app, "\ntwo")
}

test "Change to line end enters Insert mode even on an empty line" {
    testing::assert(change_empty_line() == nil)
}

fn change_empty_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "\nnext") @try
    press(&app, "c$new") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "new\nnext") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "\nnext")
}

test "editor byte conversions preserve embedded zeros and invalid UTF-8" {
    testing::assert(binary_text_roundtrip() == nil)
}

fn binary_text_roundtrip() error {
    original u8[5] := .{65, 0, 255, 192, 66}
    text := editor::owned_bytes(original[:]) @try
    defer strings::free(&text)
    testing::assert_eq(strings::len(strings::view(&text)), 5)
    bytes := editor::text_bytes(strings::view(&text)) @try
    defer lists::free<u8>(&bytes)
    view := lists::view<u8>(&bytes)
    testing::assert_eq(len(view), 5)
    i u64 := 0
    while i < 5 {
        testing::assert_eq(view[i], original[i])
        i = i + 1
    }
    return nil
}

test "display width is locale independent and rejects invalid scalars" {
    testing::assert_eq(editor::point_width(65), 1)
    testing::assert_eq(editor::point_width(30028), 2)
    testing::assert_eq(editor::point_width(769), 0)
    testing::assert_eq(editor::point_width(27), -1)
    testing::assert_eq(editor::point_width(1114112), -1)
}

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

fn press(app *editor::App, keys string) error {
    bytes := editor::text_bytes(keys) @try
    defer lists::free<u8>(&bytes)
    for byte in lists::view<u8>(&bytes) {
        editor::key(app, byte) @try
    }
    return nil
}

test "Visual line delete removes three lines and undoes as one edit" {
    testing::assert(visual_lines() == nil)
}

fn visual_lines() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo\nthree\nfour") @try
    press(&app, "Vjjd") @try
    assert_editor_text(&app, "four") @try
    testing::assert(app.mode == editor::Mode::Normal)
    press(&app, "u") @try
    return assert_editor_text(&app, "one\ntwo\nthree\nfour")
}

test "Visual characters include both endpoints in reversed Unicode selections" {
    testing::assert(visual_characters() == nil)
}

fn visual_characters() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "aé界z") @try
    press(&app, "llvhd") @try
    assert_editor_text(&app, "az") @try
    press(&app, "u") @try
    assert_editor_text(&app, "aé界z") @try
    press(&app, "v") @try
    editor::key(&app, 27) @try
    return assert_editor_text(&app, "aé界z")
}

test "Visual change and inserted replacement undo together" {
    testing::assert(visual_change() == nil)
}

fn visual_change() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc def") @try
    press(&app, "vllcXYZ") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "XYZ def") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "abc def")
}

test "Visual endpoint swap and mode switching preserve the selection anchor" {
    testing::assert(visual_endpoints() == nil)
}

fn visual_endpoints() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nijkl") @try
    press(&app, "lvlohd") @try
    assert_editor_text(&app, "d\nefgh\nijkl") @try
    press(&app, "uVjvd") @try
    return assert_editor_text(&app, "fgh\nijkl")
}

test "Visual line deletion at EOF removes the preceding separator but yanks only the line" {
    testing::assert(visual_last_line() == nil)
}

fn visual_last_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo") @try
    press(&app, "jVdp") @try
    return assert_editor_text(&app, "one\ntwo")
}

test "Visual deleting the last terminated line preserves the previous line terminator" {
    testing::assert(visual_terminated_line() == nil)
}

fn visual_terminated_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo\n") @try
    press(&app, "jVd") @try
    return assert_editor_text(&app, "one\n")
}

test "Visual line change leaves the following line separate" {
    testing::assert(visual_line_change() == nil)
}

fn visual_line_change() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\ntwo\nthree") @try
    press(&app, "VjcNEW") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "NEW\nthree") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "one\ntwo\nthree")
}

test "Visual paste replaces selected text and stores the replaced text for the next paste" {
    testing::assert(visual_put() == nil)
}

fn visual_put() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc XYZ") @try
    press(&app, "vllywvllp") @try
    assert_editor_text(&app, "abc abc") @try
    press(&app, "p") @try
    assert_editor_text(&app, "abc abcXYZ") @try
    press(&app, "uu") @try
    return assert_editor_text(&app, "abc XYZ")
}

test "Visual block delete removes columns without joining lines and undoes together" {
    testing::assert(visual_block_delete() == nil)
}

fn visual_block_delete() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nijkl") @try
    press(&app, "l") @try
    editor::key(&app, 22) @try
    press(&app, "ljjd") @try
    assert_editor_text(&app, "ad\neh\nil") @try
    press(&app, "u") @try
    assert_editor_text(&app, "abcd\nefgh\nijkl") @try
    editor::key(&app, 18) @try
    return assert_editor_text(&app, "ad\neh\nil")
}

test "Visual block retains columns across short lines and splits partially selected tabs" {
    testing::assert(visual_block_columns() == nil)
}

fn visual_block_columns() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nx\n\tZ\n界ab") @try
    press(&app, "ll") @try
    editor::key(&app, 22) @try
    press(&app, "jjjd") @try
    assert_editor_text(&app, "abd\nx\n   Z\n界b") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "abcd\nx\n\tZ\n界ab")
}

test "Block yank pastes rows at the same column and pads short lines" {
    testing::assert(visual_block_put() == nil)
}

fn visual_block_put() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nx") @try
    press(&app, "l") @try
    editor::key(&app, 22) @try
    press(&app, "ljyjjp") @try
    assert_editor_text(&app, "abcd\nefgh\nxbc\n fg") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "abcd\nefgh\nx")
}

test "Visual block change repeats inserted text across rows and undoes as one change" {
    testing::assert(visual_block_change() == nil)
}

fn visual_block_change() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nijkl") @try
    press(&app, "l") @try
    editor::key(&app, 22) @try
    press(&app, "ljjcXY") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "aXYd\neXYh\niXYl") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "abcd\nefgh\nijkl")
}

test "Visual block insert skips short rows while append pads them" {
    testing::assert(visual_block_insert() == nil)
}

fn visual_block_insert() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nx\nefgh") @try
    press(&app, "ll") @try
    editor::key(&app, 22) @try
    press(&app, "jjI!") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "ab!cd\nx\nef!gh") @try
    press(&app, "u") @try
    editor::key(&app, 22) @try
    press(&app, "jjA?") @try
    editor::key(&app, 27) @try
    assert_editor_text(&app, "abc?d\nx  ?\nefg?h") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "abcd\nx\nefgh")
}

test "Visual block dollar follows each line end when deleting and appending" {
    testing::assert(visual_block_eol() == nil)
}

fn visual_block_eol() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nef\nghijkl") @try
    press(&app, "l") @try
    editor::key(&app, 22) @try
    press(&app, "$jjd") @try
    assert_editor_text(&app, "a\ne\ng") @try
    press(&app, "uggl") @try
    editor::key(&app, 22) @try
    press(&app, "$jjA!") @try
    editor::key(&app, 27) @try
    return assert_editor_text(&app, "abcd!\nef!\nghijkl!")
}

test "Visual block paste replaces each selected row without joining lines" {
    testing::assert(visual_block_replace() == nil)
}

fn visual_block_replace() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "X\nabcd\nefgh") @try
    press(&app, "vyjl") @try
    editor::key(&app, 22) @try
    press(&app, "ljp") @try
    assert_editor_text(&app, "X\naXd\neXh") @try
    press(&app, "u") @try
    return assert_editor_text(&app, "X\nabcd\nefgh")
}

test "Visual block corner swapping keeps the rectangle while allowing the other edge to move" {
    testing::assert(visual_block_corners() == nil)
}

fn visual_block_corners() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nijkl") @try
    press(&app, "l") @try
    editor::key(&app, 22) @try
    press(&app, "ljjOhd") @try
    return assert_editor_text(&app, "d\nh\nl")
}

test "Block yank retains its width when pasting a row copied from a short line" {
    testing::assert(visual_block_width() == nil)
}

fn visual_block_width() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nx\nefgh\n1234\n5678\n9012") @try
    press(&app, "l") @try
    editor::key(&app, 22) @try
    press(&app, "ljjyjjjp") @try
    return assert_editor_text(&app, "abcd\nx\nefgh\n12bc34\n56  78\n90fg12")
}

test "Block endpoints use whole tab characters and clamp at short lines like Vim" {
    testing::assert(visual_block_endpoint("abcd\n\tZ", "\nZ") == nil)
    testing::assert(visual_block_endpoint("abcd\nx", "ad\nx") == nil)
}

fn visual_block_endpoint(text string, expected string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, text) @try
    press(&app, "ll") @try
    editor::key(&app, 22) @try
    press(&app, "jd") @try
    return assert_editor_text(&app, expected)
}

test "Visual line paste preserves line boundaries for character and unterminated line registers" {
    testing::assert(visual_line_put("one\ntwo\nthree", "vlyjVp", "one\non\nthree") == nil)
    testing::assert(visual_line_put("one\ntwo", "jyyggVp", "two\ntwo") == nil)
    testing::assert(visual_line_put("one\ntwo\nthree", "yyjvlp", "one\n\none\no\nthree") == nil)
}

fn visual_line_put(text string, keys string, expected string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, text) @try
    press(&app, keys) @try
    return assert_editor_text(&app, expected)
}

test "Normal Ctrl-w v still splits rather than starting Visual mode" {
    testing::assert(visual_split_regression() == nil)
}

fn visual_split_regression() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "text") @try
    app.active.width = 100
    app.active.height = 25
    editor::key(&app, 23) @try
    press(&app, "v") @try
    testing::assert(app.root.first != nil)
    testing::assert(app.mode == editor::Mode::Normal)
    return nil
}

test "Search extends Visual selection and restores it after the search prompt" {
    testing::assert(visual_search() == nil)
}

fn visual_search() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one target three") @try
    press(&app, "v/target") @try
    editor::key(&app, 13) @try
    press(&app, "d") @try
    return assert_editor_text(&app, "arget three")
}

test "Block change skips rows shorter than its left edge without padding them" {
    testing::assert(visual_block_short_change() == nil)
}

fn visual_block_short_change() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nx\nefgh") @try
    press(&app, "ll") @try
    editor::key(&app, 22) @try
    press(&app, "jjcX") @try
    editor::key(&app, 27) @try
    return assert_editor_text(&app, "abXd\nx\nefXh")
}

test "Block insert includes rows ending exactly at the insertion column" {
    testing::assert(visual_block_insert_edge() == nil)
}

fn visual_block_insert_edge() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nx\nefgh") @try
    press(&app, "l") @try
    editor::key(&app, 22) @try
    press(&app, "jjI!") @try
    editor::key(&app, 27) @try
    return assert_editor_text(&app, "a!bcd\nx!\ne!fgh")
}

test "Block gg updates the horizontal endpoint as well as its row" {
    testing::assert(visual_block_first_line() == nil)
}

fn visual_block_first_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nijkl") @try
    press(&app, "lljj") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "ggd") @try
    return assert_editor_text(&app, "d\nh\nl")
}

test "Visual paste with an empty register does not delete the selection" {
    testing::assert(visual_empty_put() == nil)
}

fn visual_empty_put() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "text") @try
    press(&app, "vlp") @try
    return assert_editor_text(&app, "text")
}

test "Backspacing before a block insertion cancels replication" {
    testing::assert(visual_block_backspace() == nil)
}

fn visual_block_backspace() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh") @try
    press(&app, "l") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "jI") @try
    editor::key(&app, editor::KeyBackspace) @try
    press(&app, "XY") @try
    editor::key(&app, editor::KeyEscape) @try
    return assert_editor_text(&app, "XYbcd\nefgh")
}

test "Pasting a block over character selection keeps its rows aligned" {
    testing::assert(visual_block_over_characters() == nil)
}

fn visual_block_over_characters() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "ab\ncd\n1234\n5678") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "jyjjvlp") @try
    return assert_editor_text(&app, "ab\ncd\na34\nc5678")
}

test "Pasting linewise text over a rectangle puts complete lines below the block" {
    testing::assert(visual_lines_over_block() == nil)
}

fn visual_lines_over_block() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\nabcd\nefgh") @try
    press(&app, "yyjl") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "ljp") @try
    return assert_editor_text(&app, "one\nad\neh\none")
}

test "Block yank and paste preserve combining marks attached to selected cells" {
    testing::assert(visual_block_combining() == nil)
}

fn visual_block_combining() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "áx\nb́y\n12\n34") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "jyjjp") @try
    return assert_editor_text(&app, "áx\nb́y\n1á2\n3b́4")
}

test "Ctrl-c cancels block insertion replication while preserving the typed first row" {
    testing::assert(visual_block_interrupt() == nil)
}

fn visual_block_interrupt() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh") @try
    press(&app, "l") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "jI!") @try
    editor::key(&app, editor::KeyCtrlC) @try
    return assert_editor_text(&app, "a!bcd\nefgh")
}

test "Moving horizontally after block dollar starts from the current line end" {
    testing::assert(visual_block_leave_eol() == nil)
}

fn visual_block_leave_eol() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nef\nghijkl") @try
    press(&app, "l") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "$jjhd") @try
    return assert_editor_text(&app, "a\ne\ng")
}

test "Block endpoint swap preserves the new active column for vertical movement" {
    testing::assert(visual_block_swap_motion() == nil)
}

fn visual_block_swap_motion() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd\nefgh\nijkl") @try
    press(&app, "l") @try
    editor::key(&app, editor::KeyCtrlV) @try
    press(&app, "ljojd") @try
    return assert_editor_text(&app, "abcd\neh\nijkl")
}

test "Yanking an empty final line still pastes a complete blank line" {
    testing::assert(visual_empty_line_register() == nil)
}

fn visual_empty_line_register() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc\n") @try
    press(&app, "jVyggp") @try
    return assert_editor_text(&app, "abc\n\n")
}

test "o copies mixed indentation and places typed text after it" {
    testing::assert(open_indented_line() == nil)
}

fn open_indented_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, " \t  first\nnext") @try
    editor::key(&app, 111) @try
    testing::assert(app.mode == editor::Mode::Insert)
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

test "normal b moves to the current or previous word start without changing text" {
    testing::assert(backward_word_motion() == nil)
}

fn backward_word_motion() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one  two_three 42") @try
    app.active.cursor = 16
    expected u64[4] := .{15,5,0,0}
    for at in expected {
        editor::key(&app, 98) @try
        testing::assert_eq(app.active.cursor, at)
    }
    testing::assert(app.mode == editor::Mode::Normal)
    testing::assert_eq(editor::buffer(&app).revision, 0)
    return nil
}

test "normal b crosses indentation but stops on each empty line" {
    testing::assert(backward_word_lines() == nil)
}

fn backward_word_lines() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "one\n  two\n\n\n  fin") @try
    app.active.cursor = 16
    expected u64[6] := .{14,11,10,6,0,0}
    for at in expected {
        editor::key(&app, 98) @try
        testing::assert_eq(app.active.cursor, at)
    }
    return nil
}

test "normal b separates punctuation from keyword runs and preserves UTF-8" {
    testing::assert(backward_word_punctuation() == nil)
}

fn backward_word_punctuation() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "café_name42...next\tend") @try
    app.active.cursor = 23
    expected u64[5] := .{20,15,12,0,0}
    for at in expected {
        editor::key(&app, 98) @try
        testing::assert_eq(app.active.cursor, at)
    }
    app.active.cursor = 5
    editor::key(&app, 98) @try
    testing::assert_eq(app.active.cursor, 0)
    return nil
}

test "normal b is safe in empty buffers and skips leading whitespace from EOF" {
    testing::assert(backward_word_boundaries() == nil)
}

fn backward_word_boundaries() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "") @try
    editor::key(&app, 98) @try
    testing::assert_eq(app.active.cursor, 0)
    bytes := editor::text_bytes(" \t\né") @try
    defer lists::free<u8>(&bytes)
    rope::replace(&editor::buffer(&app).text, 0, 0, lists::view<u8>(&bytes)) @try
    app.active.cursor = 5
    editor::key(&app, 98) @try
    testing::assert_eq(app.active.cursor, 3)
    editor::key(&app, 98) @try
    testing::assert_eq(app.active.cursor, 0)
    editor::key(&app, 98) @try
    testing::assert_eq(app.active.cursor, 0)
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
    testing::assert(app.mode == editor::Mode::Normal)
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

test "Arrow input split across decoder calls moves before inserting the next character" {
    testing::assert(fragmented_arrow_input() == nil)
}

fn fragmented_arrow_input() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "ab") @try
    press(&app, "A") @try
    arrow u8[3] := .{27,91,68}
    for byte in arrow[:] {
        lists::append<u8>(&app.input, byte) @try
        editor::decode(&app, false) @try
    }
    press(&app, "X") @try
    editor::key(&app, editor::KeyEscape) @try
    return assert_editor_text(&app, "aXb")
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
    p.kind = editor::PickerKind::Buffers
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
