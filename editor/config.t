package editor

use "std::lists"
use "std::strings"
use "std::memory"
use "pkg::toml"
use "std::fs"
use "std::errors"
use "std::process"
use "std::io"

const MaxConfigBytes u64 = 131072

enum MappingMode {
    Normal
    Insert
    Visual
}

enum Action {
    None
    Write
    Files
    Search
    Buffers
    Undo
    Redo
    Quit
    Split
    VSplit
    Normal
}

struct Mapping {
    mode MappingMode
    keys lists::List<u8>
    replacement lists::List<u8>
    action Action
}

struct Config {
    leader lists::List<u8>
    timeout_ms u64
    mappings lists::List<Mapping>
}

fn free_config(config *Config) {
    for mapping in lists::view<Mapping>(&config.mappings) {
        lists::free<u8>(&mapping.keys)
        lists::free<u8>(&mapping.replacement)
    }
    lists::free<Mapping>(&config.mappings)
    lists::free<u8>(&config.leader)
}

fn configure(app *App, source string) error {
    doc := zero<toml::Document>()
    defer toml::free(&doc)
    parse_error := toml::parse(source, &doc)
    app.config_line = doc.line
    if parse_error != nil {
        return parse_error
    }
    config := Config{timeout_ms: 1000}
    defer free_config(&config)
    lists::append<u8>(&config.leader, KeyComma) @try
    table_index u64 := 0
    for table in lists::view<strings::Owned>(&doc.tables) {
        app.config_line = lists::view<u64>(&doc.table_lines)[table_index]
        if strings::view(&table) != "keys" and mapping_table(strings::view(&table)) == false {
            return error("Unknown configuration table")
        }
        table_index = table_index + 1
    }
    for entry in lists::view<toml::Entry>(&doc.entries) {
        app.config_line = entry.line
        key := strings::view(&entry.key)
        if mapping_table(strings::view(&entry.table)) {
            continue
        }
        if strings::view(&entry.table) != "keys" {
            return error("Settings must be under [keys]")
        }
        if key == "leader" {
            if entry.kind != toml::Kind::Text or strings::len(strings::view(&entry.text)) == 0 {
                return error("leader must be a nonempty string")
            }
            lists::clear<u8>(&config.leader)
            key_sequence(strings::view(&entry.text), zero<u8[]>(), &config.leader) @try
        } elif key == "timeout_ms" {
            if entry.kind != toml::Kind::Integer or entry.integer == 0 or entry.integer > 60000 {
                return error("timeout_ms must be an integer between 1 and 60000")
            }
            config.timeout_ms = entry.integer
        } else {
            return error("Unknown setting under [keys]")
        }
    }
    for entry in lists::view<toml::Entry>(&doc.entries) {
        if mapping_table(strings::view(&entry.table)) == false {
            continue
        }
        app.config_line = entry.line
        if entry.kind != toml::Kind::Text {
            return error("Mapping replacements must be strings")
        }
        mapping := zero<Mapping>()
        if strings::view(&entry.table) == "keys.insert" {
            mapping.mode = MappingMode::Insert
        } elif strings::view(&entry.table) == "keys.visual" {
            mapping.mode = MappingMode::Visual
        }
        defer lists::free<u8>(&mapping.keys)
        defer lists::free<u8>(&mapping.replacement)
        key_sequence(strings::view(&entry.key), lists::view<u8>(&config.leader), &mapping.keys) @try
        replacement := strings::view(&entry.text)
        if strings::starts_with(replacement, "action:") {
            name := strings::slice(replacement, 7, strings::len(replacement)) @try
            mapping.action = mapping_action(name) @try
        } else {
            key_sequence(replacement, lists::view<u8>(&config.leader), &mapping.replacement) @try
        }
        if lists::count<u8>(&mapping.keys) == 0 {
            return error("Mapping keys must not be empty")
        }
        for byte in lists::view<u8>(&mapping.keys) {
            if byte == KeyEscape or byte == KeyCtrlC {
                return error("Esc and Ctrl-c are reserved for cancelling input")
            }
        }
        for existing in lists::view<Mapping>(&config.mappings) {
            if existing.mode == mapping.mode and lists::count<u8>(&existing.keys) == lists::count<u8>(&mapping.keys) and key_prefix(lists::view<u8>(&existing.keys), lists::view<u8>(&mapping.keys)) {
                return error("Duplicate mapping after key-token expansion")
            }
        }
        lists::append<Mapping>(&config.mappings, mapping) @try
        memory::take<Mapping>(&mapping)
    }
    free_config(&app.config)
    app.config = memory::take<Config>(&config)
    lists::clear<u8>(&app.mapping_input)
    app.mapping_deadline = 0
    app.config_line = 0
    return nil
}

fn mapping_table(name string) bool {
    return name == "keys.normal" or name == "keys.insert" or name == "keys.visual"
}

fn config_path(explicit string) (strings::Owned, error) {
    if explicit != "" {
        return strings::clone(explicit)
    }
    xdg, found, lookup_error := process::lookup_env("XDG_CONFIG_HOME")
    defer strings::free(&xdg)
    if lookup_error != nil {
        return zero<strings::Owned>(), lookup_error
    }
    base := strings::view(&xdg)
    if found and strings::starts_with(base, "/") {
        return strings::concat(base, "/omni/config.toml")
    }
    home, has_home, home_error := process::lookup_env("HOME")
    defer strings::free(&home)
    if home_error != nil {
        return zero<strings::Owned>(), home_error
    }
    if has_home and strings::starts_with(strings::view(&home), "/") {
        return strings::concat(strings::view(&home), "/.config/omni/config.toml")
    }
    return strings::clone("")
}

fn load_config(app *App, explicit string, disabled bool) error {
    configure(app, "") @try
    if disabled {
        return nil
    }
    path := config_path(explicit) @try
    defer strings::free(&path)
    name := strings::view(&path)
    if name == "" {
        return nil
    }
    err := read_config(app, name, explicit != "")
    if err != nil {
        diagnostic := lists::create<u8>()
        defer lists::free<u8>(&diagnostic)
        append_text(&diagnostic, "Configuration error: ") @try
        // Never print terminal controls embedded in a path.
        path_bytes := text_bytes(name) @try
        defer lists::free<u8>(&path_bytes)
        for byte in lists::view<u8>(&path_bytes) {
            safe := byte
            if byte < 32 or byte == 127 {
                safe = ByteQuestion
            }
            lists::append<u8>(&diagnostic, safe) @try
        }
        if app.config_line > 0 {
            append_text(&diagnostic, ":") @try
            number(&diagnostic, app.config_line) @try
        }
        message := owned_bytes(lists::view<u8>(&diagnostic)) @try
        defer strings::free(&message)
        io::println(strings::view(&message))
        return err
    }
    return nil
}

fn read_config(app *App, path string, required bool) error {
    metadata, stat_error := fs::stat(path)
    if stat_error != nil {
        if stat_error.kind == errors::Error::NotFound and required == false {
            return nil
        }
        return stat_error
    }
    if metadata.kind != fs::FileType::Regular or metadata.size > MaxConfigBytes {
        return error("Config must be a regular file no larger than 128 KiB")
    }
    source := fs::read_file(path) @try
    defer strings::free(&source)
    if strings::len(strings::view(&source)) > MaxConfigBytes {
        return error("Config exceeds 128 KiB")
    }
    return configure(app, strings::view(&source))
}
