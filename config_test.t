package main

use "pkg::toml"
use "pkg::editor"
use "std::lists"
use "std::strings"
use "std::testing"

test "TOML reads a quoted leader under a table header" {
    testing::assert(toml_leader() == nil)
}

fn toml_leader() error {
    doc := zero<toml::Document>()
    defer toml::free(&doc)
    toml::parse("[keys]\nleader = \"!\"\n", &doc) @try
    entry := toml::get(&doc, "keys", "leader")
    testing::assert(entry != nil)
    testing::assert(entry.kind == toml::Kind::Text)
    testing::assert_eq(strings::view(&entry.text), "!")
    return nil
}

test "TOML reads typed integers and booleans while ignoring comments" {
    testing::assert(toml_settings() == nil)
}

fn toml_settings() error {
    doc := zero<toml::Document>()
    defer toml::free(&doc)
    toml::parse("# settings\n[keys]\ntimeout_ms = 1_000 # wait\n[tools]\nauto_install = false\n", &doc) @try
    timeout := toml::get(&doc, "keys", "timeout_ms")
    testing::assert(timeout != nil)
    testing::assert(timeout.kind == toml::Kind::Integer)
    testing::assert_eq(timeout.integer, 1000)
    tools := toml::get(&doc, "tools", "auto_install")
    testing::assert(tools != nil)
    testing::assert(tools.kind == toml::Kind::Boolean)
    testing::assert(tools.boolean == false)
    return nil
}

test "TOML preserves quoted mapping keys and distinguishes basic from literal strings" {
    testing::assert(toml_mapping_strings() == nil)
}

fn toml_mapping_strings() error {
    doc := zero<toml::Document>()
    defer toml::free(&doc)
    toml::parse("[keys.normal]\n\"<leader>#\" = \"i\\\"hi\\\"<Esc>\" # comment\nliteral = 'a\\b'\n", &doc) @try
    entry := toml::get(&doc, "keys.normal", "<leader>#")
    testing::assert(entry != nil)
    testing::assert_eq(strings::view(&entry.text), "i\"hi\"<Esc>")
    literal := toml::get(&doc, "keys.normal", "literal")
    testing::assert(literal != nil)
    testing::assert_eq(strings::view(&literal.text), "a\\b")
    return nil
}

test "TOML rejects duplicate tables and malformed dotted table names" {
    testing::assert(toml_rejects("[keys]\na = 1\n[keys]\nb = 2\n", 3) == nil)
    testing::assert(toml_rejects("[keys..normal]\na = 1\n", 1) == nil)
}

fn toml_rejects(source string, line u64) error {
    doc := zero<toml::Document>()
    defer toml::free(&doc)
    err := toml::parse(source, &doc)
    testing::assert(err != nil)
    testing::assert_eq(doc.line, line)
    return nil
}

test "Editor configuration reads the leader and mapping timeout with safe defaults" {
    testing::assert(editor_config_settings() == nil)
}

fn editor_config_settings() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    editor::configure(&app, "[keys]\nleader = '!'\ntimeout_ms = 250\n") @try
    leader := lists::view<u8>(&app.config.leader)
    testing::assert_eq(len(leader), 1)
    testing::assert_eq(leader[0], 33)
    testing::assert_eq(app.config.timeout_ms, 250)
    editor::configure(&app, "") @try
    testing::assert_eq(lists::view<u8>(&app.config.leader)[0], 44)
    testing::assert_eq(app.config.timeout_ms, 1000)
    return nil
}

test "Normal mappings expand the configured leader and execute key sequences" {
    testing::assert(normal_leader_mapping() == nil)
}

fn normal_leader_mapping() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "text") @try
    editor::configure(&app, "[keys.normal]\n'<leader>z' = 'iOK<Esc>'\n[keys]\nleader = '!'\n") @try
    press(&app, "!z") @try
    testing::assert(app.mode == editor::Mode::Normal)
    return assert_editor_text(&app, "OKtext")
}

test "Mappings are mode-specific and replacement keys are not recursively remapped" {
    testing::assert(mode_specific_mappings() == nil)
}

fn mode_specific_mappings() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc") @try
    editor::configure(&app, "[keys.normal]\nx = 'l'\nl = 'x'\n[keys.insert]\njk = '<Esc>'\n[keys.visual]\nq = 'd'\n") @try
    press(&app, "x") @try
    testing::assert_eq(app.active.cursor, 1)
    assert_editor_text(&app, "abc") @try
    press(&app, "iHELLOjk") @try
    testing::assert(app.mode == editor::Mode::Normal)
    assert_editor_text(&app, "aHELLObc") @try
    press(&app, "0vq") @try
    return assert_editor_text(&app, "HELLObc")
}

test "Ambiguous mapping prefixes wait and mismatches execute the shorter match before remapping the suffix" {
    testing::assert(ambiguous_mappings() == nil)
}

fn ambiguous_mappings() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc") @try
    editor::configure(&app, "[keys.normal]\ng = 'l'\ngg = '$'\nx = 'i!<Esc>'\n") @try
    press(&app, "g") @try
    testing::assert_eq(app.active.cursor, 0)
    press(&app, "g") @try
    testing::assert_eq(app.active.cursor, 3)
    press(&app, "0gx") @try
    return assert_editor_text(&app, "a!bc")
}

test "Mappings can invoke named undo and redo actions" {
    testing::assert(named_mapping_actions() == nil)
}

fn named_mapping_actions() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc") @try
    editor::configure(&app, "[keys.normal]\n'<leader>u' = 'action:undo'\n'<leader>r' = 'action:redo'\n") @try
    press(&app, "ix") @try
    editor::key(&app, editor::KeyEscape) @try
    press(&app, ",u") @try
    assert_editor_text(&app, "abc") @try
    press(&app, ",r") @try
    return assert_editor_text(&app, "xabc")
}

test "Escape cancels Normal mapping prefixes and preserves pending Insert text" {
    testing::assert(cancel_mapping_prefix() == nil)
}

fn cancel_mapping_prefix() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc") @try
    editor::configure(&app, "[keys.normal]\ng = 'l'\ngg = '$'\n[keys.insert]\njk = '<Esc>'\n") @try
    press(&app, "g") @try
    editor::key(&app, editor::KeyEscape) @try
    testing::assert_eq(app.active.cursor, 0)
    press(&app, "ij") @try
    editor::key(&app, editor::KeyEscape) @try
    testing::assert(app.mode == editor::Mode::Normal)
    return assert_editor_text(&app, "jabc")
}

test "Mappings understand Space leaders and literal, tab, backspace and Enter key tokens" {
    testing::assert(mapping_key_tokens() == nil)
}

fn mapping_key_tokens() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "") @try
    editor::configure(&app, "[keys]\nleader = '<Space>'\n[keys.normal]\n'<leader>x' = 'i<lt><Tab>A<BS>B<CR>Z<Esc>'\n'<C-a>' = 'action:undo'\n") @try
    press(&app, " x") @try
    assert_editor_text(&app, "<\tB\nZ") @try
    editor::key(&app, 1) @try
    return assert_editor_text(&app, "")
}

test "Configuration rejects duplicate expanded mappings without replacing working settings" {
    testing::assert(duplicate_expanded_mapping() == nil)
}

fn duplicate_expanded_mapping() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc") @try
    editor::configure(&app, "[keys]\nleader = '!'\n[keys.normal]\n'<leader>x' = 'i!<Esc>'\n") @try
    err := editor::configure(&app, "[keys.normal]\n'<leader>x' = '0'\n',x' = '$'\n")
    testing::assert(err != nil)
    press(&app, "!x") @try
    return assert_editor_text(&app, "!abc")
}

test "Configuration reserves Escape and Ctrl-c as reliable cancellation keys" {
    testing::assert(reserved_mapping_keys() == nil)
}

fn reserved_mapping_keys() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    err := editor::configure(&app, "[keys.normal]\n'<Esc>' = 'i'\n")
    testing::assert(err != nil)
    second := editor::configure(&app, "[keys.insert]\n'j<C-c>' = '<Esc>'\n")
    testing::assert(second != nil)
    return nil
}

test "Arrow input flushes pending Insert mapping text before moving the cursor" {
    testing::assert(mapping_arrow_flush() == nil)
}

fn mapping_arrow_flush() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "") @try
    editor::configure(&app, "[keys.insert]\njk = '<Esc>'\n") @try
    press(&app, "ij") @try
    arrow u8[3] := .{27,91,68}
    lists::append_slice<u8>(&app.input, arrow[:]) @try
    editor::decode(&app, false) @try
    press(&app, "x") @try
    editor::key(&app, editor::KeyEscape) @try
    return assert_editor_text(&app, "xj")
}

test "Bracketed paste flushes pending text and bypasses Insert mappings" {
    testing::assert(mapping_paste_literal() == nil)
}

fn mapping_paste_literal() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "") @try
    editor::configure(&app, "[keys.insert]\njk = '<Esc>'\n") @try
    press(&app, "ij") @try
    paste u8[14] := .{27,91,50,48,48,126,106,107,27,91,50,48,49,126}
    lists::append_slice<u8>(&app.input, paste[:]) @try
    editor::decode(&app, false) @try
    testing::assert(app.mode == editor::Mode::Insert)
    editor::key(&app, editor::KeyEscape) @try
    return assert_editor_text(&app, "jjk")
}

test "Unknown configuration tables report their header line" {
    testing::assert(unknown_config_table_line() == nil)
}

fn unknown_config_table_line() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    err := editor::configure(&app, "# example\n[wrong]\nx = 'l'\n")
    testing::assert(err != nil)
    testing::assert_eq(app.config_line, 2)
    return nil
}

test "TOML rejects duplicate keys, malformed scalars and unsupported forms" {
    testing::assert(toml_rejects("[keys]\nleader = ','\nleader = '!'\n", 3) == nil)
    testing::assert(toml_rejects("timeout = 01\n", 1) == nil)
    testing::assert(toml_rejects("timeout = 1__0\n", 1) == nil)
    testing::assert(toml_rejects("timeout = 9223372036854775808\n", 1) == nil)
    testing::assert(toml_rejects("timeout = 1.5\n", 1) == nil)
    testing::assert(toml_rejects("enabled = False\n", 1) == nil)
    testing::assert(toml_rejects("extensions = ['go']\n", 1) == nil)
    testing::assert(toml_rejects("leader = \"\\q\"\n", 1) == nil)
    testing::assert(toml_rejects("leader = '!' garbage\n", 1) == nil)
}

test "Configuration rejects unknown settings, invalid timeouts and unknown key tokens" {
    testing::assert(config_rejects("[keys]\ntimeot_ms = 1000\n") == nil)
    testing::assert(config_rejects("[keys]\ntimeout_ms = 0\n") == nil)
    testing::assert(config_rejects("[keys]\ntimeout_ms = 60001\n") == nil)
    testing::assert(config_rejects("[keys]\ntimeout_ms = '1000'\n") == nil)
    testing::assert(config_rejects("[keys]\nleader = ''\n") == nil)
    testing::assert(config_rejects("[keys.normal]\nx = true\n") == nil)
    testing::assert(config_rejects("[keys.normal]\nx = '<NotAKey>'\n") == nil)
    testing::assert(config_rejects("[keys.normal]\nx = 'action:unknown'\n") == nil)
}

fn config_rejects(source string) error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    err := editor::configure(&app, source)
    testing::assert(err != nil)
    return nil
}

test "Mapping prefixes have no effect before their deadline and fall back after it" {
    testing::assert(mapping_timeout() == nil)
}

fn mapping_timeout() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)") @try
    editor::configure(&app, "[keys.normal]\n'<leader>x' = '0'\n") @try
    press(&app, "f)f),") @try
    changed := editor::expire_mappings(&app, 0) @try
    testing::assert(changed == false)
    testing::assert_eq(app.active.cursor, 7)
    expired := editor::expire_mappings(&app, editor::monotonic_ms() + 1001) @try
    testing::assert(expired)
    testing::assert_eq(app.active.cursor, 3)
    return nil
}

test "Mappings do not intercept character-find targets or operator-pending input" {
    testing::assert(mapping_command_contexts() == nil)
}

fn mapping_command_contexts() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "a(b)c(d)") @try
    editor::configure(&app, "[keys.normal]\n')' = 'x'\nw = 'x'\n") @try
    press(&app, "f)") @try
    testing::assert_eq(app.active.cursor, 3)
    press(&app, "0dw") @try
    return assert_editor_text(&app, "(b)c(d)")
}

test "TOML rejects control bytes even inside comments" {
    testing::assert(toml_comment_controls() == nil)
}

fn toml_comment_controls() error {
    doc := zero<toml::Document>()
    defer toml::free(&doc)
    bytes u8[3] := .{35,0,10}
    source := strings::from_bytes(bytes[:]) @try
    defer strings::free(&source)
    err := toml::parse(strings::view(&source), &doc)
    testing::assert(err != nil)
    testing::assert_eq(doc.line, 1)
    return nil
}

test "A mapping stops playing replacement keys when the editor quits" {
    testing::assert(mapping_stops_at_quit() == nil)
}

fn mapping_stops_at_quit() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abc") @try
    editor::configure(&app, "[keys.normal]\nQ = ':qa!<CR>ix'\n") @try
    press(&app, "Q") @try
    testing::assert(app.quit)
    return assert_editor_text(&app, "abc")
}

test "TOML accepts CRLF lines and retains typed values" {
    testing::assert(toml_crlf() == nil)
}

fn toml_crlf() error {
    doc := zero<toml::Document>()
    defer toml::free(&doc)
    bytes u8[9] := .{107,61,49,13,10,35,9,13,10}
    source := strings::from_bytes(bytes[:]) @try
    defer strings::free(&source)
    toml::parse(strings::view(&source), &doc) @try
    entry := toml::get(&doc, "", "k")
    testing::assert(entry != nil)
    testing::assert(entry.kind == toml::Kind::Integer)
    testing::assert_eq(entry.integer, 1)
    testing::assert_eq(doc.line, 3)
    return nil
}

test "Physical arrows do not trigger mappings for their equivalent Visual motion letters" {
    testing::assert(visual_arrow_mapping_boundary() == nil)
}

fn visual_arrow_mapping_boundary() error {
    app := zero<editor::App>()
    defer editor::free_app(&app)
    setup_editor(&app, "abcd") @try
    editor::configure(&app, "[keys.visual]\nh = 'd'\n") @try
    press(&app, "vll") @try
    arrow u8[3] := .{27,91,68}
    lists::append_slice<u8>(&app.input, arrow[:]) @try
    editor::decode(&app, false) @try
    testing::assert(app.mode == editor::Mode::VisualCharacter)
    testing::assert_eq(app.active.cursor, 1)
    return assert_editor_text(&app, "abcd")
}
