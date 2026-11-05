package toml

use "std::lists"
use "std::strings"
use "std::memory"
use "std::unicode::utf8"

enum Kind {
    Text
    Integer
    Boolean
}

struct Entry {
    line u64
    table strings::Owned
    key strings::Owned
    text strings::Owned
    kind Kind
    integer u64
    boolean bool
}

struct Document {
    entries lists::List<Entry>
    tables lists::List<strings::Owned>
    table_lines lists::List<u64>
    line u64
}

struct Parser {
    bytes u8[]
    at u64
}

fn peek(p *Parser) u8 {
    if p.at >= len(p.bytes) {
        return 0
    }
    return p.bytes[p.at]
}

fn spaces(p *Parser) {
    while peek(p) == 32 or peek(p) == 9 {
        p.at = p.at + 1
    }
}

fn bare(byte u8) bool {
    return (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) or (byte >= 48 and byte <= 57) or byte == 95 or byte == 45
}

fn text(p *Parser) (strings::Owned, error) {
    quote := peek(p)
    p.at = p.at + 1
    out := lists::create<u8>()
    defer lists::free<u8>(&out)
    while p.at < len(p.bytes) and peek(p) != quote {
        byte := peek(p)
        if (byte < 32 and byte != 9) or byte == 127 {
            return zero<strings::Owned>(), error("TOML strings must be single-line")
        }
        p.at = p.at + 1
        if quote == 34 and byte == 92 {
            byte = peek(p)
            p.at = p.at + 1
            if byte == 110 {
                byte = 10
            } elif byte == 116 {
                byte = 9
            } elif byte == 114 {
                byte = 13
            } elif byte == 98 {
                byte = 8
            } elif byte == 102 {
                byte = 12
            } elif byte != 34 and byte != 92 {
                return zero<strings::Owned>(), error("Unsupported TOML string escape")
            }
        }
        lists::append<u8>(&out, byte) @try
    }
    if p.at >= len(p.bytes) {
        return zero<strings::Owned>(), error("Unterminated TOML string")
    }
    value := strings::from_bytes(lists::view<u8>(&out)) @try
    p.at = p.at + 1
    return value, nil
}

fn value(p *Parser, entry *Entry) error {
    if peek(p) == 34 or peek(p) == 39 {
        entry.text = text(p) @try
        return nil
    }
    start := p.at
    while p.at < len(p.bytes) and peek(p) != 32 and peek(p) != 9 and peek(p) != 10 and peek(p) != 13 and peek(p) != 35 {
        p.at = p.at + 1
    }
    token := strings::from_bytes(p.bytes[start:p.at] @try) @try
    defer strings::free(&token)
    word := strings::view(&token)
    if word == "true" or word == "false" {
        entry.kind = Kind::Boolean
        entry.boolean = word == "true"
        return nil
    }
    at := start
    if at < p.at and p.bytes[at] == 43 {
        at = at + 1
    }
    first := at
    digit := false
    digits u64 := 0
    while at < p.at {
        byte := p.bytes[at]
        if byte == 95 and digit {
            digit = false
        } elif byte >= 48 and byte <= 57 {
            number := widen<u64>(byte - 48)
            if entry.integer > (9223372036854775807 - number) / 10 {
                return error("TOML integer is too large")
            }
            entry.integer = entry.integer * 10 + number
            digit = true
            digits = digits + 1
        } else {
            return error("Unsupported TOML value; expected string, nonnegative decimal integer or boolean")
        }
        at = at + 1
    }
    if digit == false or (digits > 1 and p.bytes[first] == 48) {
        return error("Invalid TOML decimal integer")
    }
    entry.kind = Kind::Integer
    return nil
}

fn free(doc *Document) {
    for entry in lists::view<Entry>(&doc.entries) {
        strings::free(&entry.table)
        strings::free(&entry.key)
        strings::free(&entry.text)
    }
    lists::free<Entry>(&doc.entries)
    for table in lists::view<strings::Owned>(&doc.tables) {
        strings::free(&table)
    }
    lists::free<strings::Owned>(&doc.tables)
    lists::free<u64>(&doc.table_lines)
}

fn get(doc *Document, table string, key string) *Entry {
    entries := lists::view<Entry>(&doc.entries)
    i u64 := 0
    while i < len(entries) {
        if strings::view(&entries[i].table) == table and strings::view(&entries[i].key) == key {
            return &entries[i]
        }
        i = i + 1
    }
    return nil
}

fn has_table(doc *Document, name string) bool {
    for table in lists::view<strings::Owned>(&doc.tables) {
        if strings::view(&table) == name {
            return true
        }
    }
    return false
}

fn parse(source string, doc *Document) error {
    doc.line = 1
    utf8::validate(source) @try
    data := strings::to_bytes(source) @try
    defer lists::free<u8>(&data)
    p := Parser{bytes: lists::view<u8>(&data)}
    table := strings::Owned{}
    defer strings::free(&table)
    while p.at < len(p.bytes) {
        spaces(&p)
        byte := peek(&p)
        if byte == 91 {
            p.at = p.at + 1
            start := p.at
            segment := false
            while bare(peek(&p)) or peek(&p) == 46 {
                if peek(&p) == 46 {
                    if segment == false {
                        return error("Empty TOML table name segment")
                    }
                    segment = false
                } else {
                    segment = true
                }
                p.at = p.at + 1
            }
            if segment == false or peek(&p) != 93 {
                return error("Invalid or unsupported TOML table header")
            }
            name := strings::from_bytes(p.bytes[start:p.at] @try) @try
            defer strings::free(&name)
            if has_table(doc, strings::view(&name)) {
                return error("Duplicate TOML table")
            }
            next_table := strings::clone(strings::view(&name)) @try
            defer strings::free(&next_table)
            lists::append<strings::Owned>(&doc.tables, name) @try
            memory::take<strings::Owned>(&name)
            lists::append<u64>(&doc.table_lines, doc.line) @try
            strings::free(&table)
            table = memory::take<strings::Owned>(&next_table)
            p.at = p.at + 1
        } elif byte != 35 and byte != 10 and byte != 13 and p.at < len(p.bytes) {
            entry := zero<Entry>()
            entry.line = doc.line
            defer strings::free(&entry.table)
            defer strings::free(&entry.key)
            defer strings::free(&entry.text)
            entry.table = strings::clone(strings::view(&table)) @try
            if byte == 34 or byte == 39 {
                entry.key = text(&p) @try
            } else {
                start := p.at
                while bare(peek(&p)) {
                    p.at = p.at + 1
                }
                if start == p.at {
                    return error("Invalid or unsupported TOML key")
                }
                entry.key = strings::from_bytes(p.bytes[start:p.at] @try) @try
            }
            spaces(&p)
            if peek(&p) != 61 {
                return error("Expected '=' after TOML key")
            }
            p.at = p.at + 1
            spaces(&p)
            value(&p, &entry) @try
            if get(doc, strings::view(&entry.table), strings::view(&entry.key)) != nil {
                return error("Duplicate TOML key")
            }
            lists::append<Entry>(&doc.entries, entry) @try
            memory::take<Entry>(&entry)
        }
        spaces(&p)
        if peek(&p) == 35 {
            while p.at < len(p.bytes) and peek(&p) != 10 and peek(&p) != 13 {
                if (peek(&p) < 32 and peek(&p) != 9) or peek(&p) == 127 {
                    return error("Control byte in TOML comment")
                }
                p.at = p.at + 1
            }
        }
        if peek(&p) == 13 {
            p.at = p.at + 1
            if peek(&p) != 10 {
                return error("Expected LF after CR in TOML")
            }
        }
        if peek(&p) == 10 {
            doc.line = doc.line + 1
            p.at = p.at + 1
        } elif p.at < len(p.bytes) {
            return error("Unexpected text after TOML value")
        }
    }
    return nil
}
