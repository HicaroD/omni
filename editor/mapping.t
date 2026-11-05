package editor

use "std::lists"
use "std::strings"
use "std::memory"

const MaxMappingBytes u64 = 256

fn key_sequence(source string, leader u8[], out *lists::List<u8>) error {
    data := text_bytes(source) @try
    defer lists::free<u8>(&data)
    bytes := lists::view<u8>(&data)
    at u64 := 0
    while at < len(bytes) {
        if bytes[at] != KeyLess {
            lists::append<u8>(out, bytes[at]) @try
            at = at + 1
        } else {
            end := at + 1
            while end < len(bytes) and bytes[end] != KeyGreater {
                end = end + 1
            }
            if end == len(bytes) {
                return error("Unclosed key token; use <lt> for a literal '<'")
            }
            token := owned_bytes(bytes[at + 1:end] @try) @try
            defer strings::free(&token)
            name := strings::view(&token)
            if name == "leader" and len(leader) > 0 {
                lists::append_slice<u8>(out, leader) @try
            } elif name == "Esc" {
                lists::append<u8>(out, KeyEscape) @try
            } elif name == "Space" {
                lists::append<u8>(out, ByteSpace) @try
            } elif name == "Tab" {
                lists::append<u8>(out, KeyTab) @try
            } elif name == "CR" or name == "Enter" {
                lists::append<u8>(out, KeyEnter) @try
            } elif name == "BS" {
                lists::append<u8>(out, KeyDelete) @try
            } elif name == "lt" {
                lists::append<u8>(out, KeyLess) @try
            } elif end - at == 4 and bytes[at + 1] == KeyUpperC and bytes[at + 2] == KeyMinus {
                control := bytes[at + 3]
                if control >= AsciiLowerFirst and control <= AsciiLowerLast {
                    control = control - (AsciiLowerFirst - 1)
                } elif control >= AsciiUpperFirst - 1 and control <= ByteUnderscore {
                    control = control - (AsciiUpperFirst - 1)
                } else {
                    return error("Unsupported Ctrl key token")
                }
                lists::append<u8>(out, control) @try
            } else {
                return error("Unknown key token")
            }
            at = end + 1
        }
        if lists::count<u8>(out) > MaxMappingBytes {
            return error("Key sequence exceeds 256 bytes")
        }
    }
    return nil
}

fn key_prefix(prefix u8[], sequence u8[]) bool {
    if len(prefix) > len(sequence) {
        return false
    }
    i u64 := 0
    while i < len(prefix) {
        if prefix[i] != sequence[i] {
            return false
        }
        i = i + 1
    }
    return true
}

fn current_mapping_mode(app *App) MappingMode {
    if app.mode == Mode::Insert {
        return MappingMode::Insert
    }
    if visual(app) {
        return MappingMode::Visual
    }
    return MappingMode::Normal
}

fn execute_mapping(app *App, mapping *Mapping) error {
    if mapping.action != Action::None {
        return execute_action(app, mapping.action)
    }
    for replacement in lists::view<u8>(&mapping.replacement) {
        if app.quit {
            break
        }
        builtin_key(app, replacement) @try
    }
    return nil
}

fn resolve_mapping(app *App) error {
    held := memory::take<lists::List<u8>>(&app.mapping_input)
    defer lists::free<u8>(&held)
    app.mapping_deadline = 0
    bytes := lists::view<u8>(&held)
    if len(bytes) == 0 {
        return nil
    }
    mappings := lists::view<Mapping>(&app.config.mappings)
    chosen u64 := 0
    used u64 := 0
    i u64 := 0
    while i < len(mappings) {
        mapping := &mappings[i]
        keys := lists::view<u8>(&mapping.keys)
        if mapping.mode == app.mapping_mode and len(keys) > used and key_prefix(keys, bytes) {
            chosen = i + 1
            used = len(keys)
        }
        i = i + 1
    }
    if chosen > 0 {
        execute_mapping(app, &mappings[chosen - 1]) @try
    } else {
        builtin_key(app, bytes[0]) @try
        used = 1
    }
    while used < len(bytes) and app.quit == false {
        key(app, bytes[used]) @try
        used = used + 1
    }
    return nil
}

fn expire_mappings(app *App, now u64) (bool, error) {
    if lists::count<u8>(&app.mapping_input) > 0 and now >= app.mapping_deadline {
        resolve_mapping(app) @try
        return true, nil
    }
    return false, nil
}

fn cancel_mapping(app *App, literal bool) error {
    held := memory::take<lists::List<u8>>(&app.mapping_input)
    defer lists::free<u8>(&held)
    app.mapping_deadline = 0
    if literal {
        for byte in lists::view<u8>(&held) {
            builtin_key(app, byte) @try
        }
    }
    return nil
}

fn pending_mapping_label(app *App) (strings::Owned, error) {
    text := lists::create<u8>()
    defer lists::free<u8>(&text)
    append_text(&text, "Keys: ") @try
    for byte in lists::view<u8>(&app.mapping_input) {
        if byte == ByteSpace {
            append_text(&text, "<Space>") @try
        } elif byte == KeyTab {
            append_text(&text, "<Tab>") @try
        } elif byte < ByteSpace {
            append_text(&text, "<C-") @try
            lists::append<u8>(&text, byte + 64) @try
            append_text(&text, ">") @try
        } elif byte == KeyDelete {
            append_text(&text, "<BS>") @try
        } else {
            lists::append<u8>(&text, byte) @try
        }
    }
    return owned_bytes(lists::view<u8>(&text))
}

fn key(app *App, byte u8) error {
    now := monotonic_ms()
    expire_mappings(app, now) @try
    if byte == KeyEscape or byte == KeyCtrlC {
        cancel_mapping(app, app.mode == Mode::Insert) @try
        return builtin_key(app, byte)
    }
    if lists::count<Mapping>(&app.config.mappings) == 0 or (app.mode != Mode::Normal and app.mode != Mode::Insert and visual(app) == false) or app.pending != 0 or app.count != 0 or app.character_find.motion != 0 or app.picker.kind != PickerKind::None or app.block_insert {
        return builtin_key(app, byte)
    }
    if lists::count<u8>(&app.mapping_input) == 0 {
        app.mapping_mode = current_mapping_mode(app)
    }
    lists::append<u8>(&app.mapping_input, byte) @try
    prefix := false
    longer := false
    exact u64 := 0
    mappings := lists::view<Mapping>(&app.config.mappings)
    i u64 := 0
    while i < len(mappings) {
        mapping := &mappings[i]
        if mapping.mode == app.mapping_mode and key_prefix(lists::view<u8>(&app.mapping_input), lists::view<u8>(&mapping.keys)) {
            prefix = true
            if lists::count<u8>(&app.mapping_input) == lists::count<u8>(&mapping.keys) {
                exact = i + 1
            } else {
                longer = true
            }
        }
        i = i + 1
    }
    if exact > 0 and longer == false {
        lists::clear<u8>(&app.mapping_input)
        app.mapping_deadline = 0
        return execute_mapping(app, &mappings[exact - 1])
    }
    if prefix {
        app.mapping_deadline = now + app.config.timeout_ms
        return nil
    }
    return resolve_mapping(app)
}
