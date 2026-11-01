package editor

use "std::lists"
use "std::strings"
use "std::memory"
use "pkg::rope"
use "std::process"

struct Item {
    path strings::Owned
    label strings::Owned
    line u64
    column u64
    buffer u64
}

struct Match {
    index u64
    score u64
}

struct Picker {
    changed bool
    kind i32
    process process::Child
    running bool
    items lists::List<Item>
    matches lists::List<Match>
    query lists::List<u8>
    pending lists::List<u8>
    selected u64
    hidden bool
    ignored bool
    regex bool
    limited bool
    failed bool
    preview rope::Rope
    preview_key u64
    preview_ready bool
}

fn free_items(p *Picker) {
    items := lists::view<Item>(&p.items)
    i u64 := 0
    while i < len(items) {
        item := &items[i]
        strings::free(&item.path)
        strings::free(&item.label)
        i = i + 1
    }
    lists::clear<Item>(&p.items)
    lists::clear<Match>(&p.matches)
}

fn close_picker(p *Picker) {
    process::close_child(&p.process)
    p.running = false
    free_items(p)
    lists::free<Item>(&p.items)
    lists::free<Match>(&p.matches)
    lists::free<u8>(&p.query)
    lists::free<u8>(&p.pending)
    rope::free(&p.preview)
    p.kind = 0
    p.preview_ready = false
}

fn restart_picker(p *Picker) error {
    process::close_child(&p.process) @try
    p.running = false
    free_items(p)
    lists::clear<u8>(&p.pending)
    p.selected = 0
    p.limited = false
    p.failed = false
    p.preview_ready = false
    query := owned_bytes(lists::view<u8>(&p.query)) @catch err {
        return err
    }
    defer strings::free(&query)
    kind i32 := 0
    if p.kind == 2 {
        kind = 1
        if lists::count<u8>(&p.query) == 0 {
            return nil
        }
    }
    child := spawn_search(kind, strings::view(&query), p.hidden, p.ignored, p.regex) @catch err {
        p.failed = true
        return nil
    }
    p.process = memory::take<process::Child>(&child)
    p.running = true
    return nil
}

fn start_picker(app *App, kind i32) error {
    close_picker(&app.picker)
    p := &app.picker
    p.kind = kind
    p.selected = 0
    p.hidden = false
    p.ignored = false
    p.regex = false
    if kind == 3 {
        buffers := lists::view<*Buffer>(&app.buffers)
        i u64 := 0
        while i < len(buffers) {
            buf := buffers[i]
            name := strings::view(&buf.path)
            if name == "" {
                name = "[No Name]"
            }
            label := strings::clone(name) @catch err {
                return err
            }
            item := Item{label: label, buffer: i}
            lists::append<Item>(&p.items, item) @catch err {
                strings::free(&label)
                return err
            }
            i = i + 1
        }
        return filter_picker(p)
    }
    return restart_picker(p)
}

fn fold(b u8) u8 {
    if b >= 65 and b <= 90 {
        return b + 32
    }
    return b
}

fn fuzzy(label string, query u8[]) (u64, bool) {
    if len(query) == 0 {
        return 0, true
    }
    text := text_bytes(label) @catch err {
        return 0, false
    }
    defer lists::free<u8>(&text)
    bytes := lists::view<u8>(&text)
    q u64 := 0
    i u64 := 0
    score u64 := 0
    run u64 := 0
    while i < len(bytes) and q < len(query) {
        if fold(bytes[i]) == fold(query[q]) {
            score = score + 10 + run * 5
            if i == 0 {
                score = score + 20
            } else {
                if bytes[i - 1] == 47 or bytes[i - 1] == 95 or bytes[i - 1] == 45 {
                    score = score + 20
                }
            }
            run = run + 1
            q = q + 1
        } else {
            run = 0
        }
        i = i + 1
    }
    return score, q == len(query)
}

fn filter_picker(p *Picker) error {
    lists::clear<Match>(&p.matches)
    items := lists::view<Item>(&p.items)
    i u64 := 0
    while i < len(items) {
        index := i
        i = i + 1
        score u64 := 0
        found := true
        if p.kind != 2 {
            rank, ok := fuzzy(strings::view(&items[index].label), lists::view<u8>(&p.query))
            score = rank
            found = ok
        }
        if found == false {
            continue
        }
        count := lists::count<Match>(&p.matches)
        current := lists::view<Match>(&p.matches)
        if count == 100 and score <= current[99].score {
            continue
        }
        if count < 100 {
            lists::append<Match>(&p.matches, Match{index: index, score: score}) @try
        } else {
            current[99] = Match{index: index, score: score}
        }
        ranked := lists::view<Match>(&p.matches)
        pos := len(ranked) - 1
        while pos > 0 and ranked[pos].score > ranked[pos - 1].score {
            temp := ranked[pos]
            ranked[pos] = ranked[pos - 1]
            ranked[pos - 1] = temp
            pos = pos - 1
        }
    }
    count2 := lists::count<Match>(&p.matches)
    if count2 == 0 {
        p.selected = 0
    } else {
        p.selected = min(p.selected, count2 - 1)
    }
    return nil
}

fn parse_decimal(bytes u8[], start u64, end u64) u64 {
    value u64 := 0
    digits u8[10] := .{48,49,50,51,52,53,54,55,56,57}
    i := start
    while i < end {
        d u64 := 0
        while d < 10 and digits[d] != bytes[i] {
            d = d + 1
        }
        if d == 10 or value > 1000000000 {
            return 0
        }
        value = value * 10 + d
        i = i + 1
    }
    return value
}

fn add_record(p *Picker, bytes u8[]) error {
    path_end := len(bytes)
    line u64 := 0
    column u64 := 0
    if p.kind == 2 {
        path_end = 0
        while path_end < len(bytes) and bytes[path_end] != 0 {
            path_end = path_end + 1
        }
        a := path_end + 1
        colon := a
        while colon < len(bytes) and bytes[colon] != 58 {
            colon = colon + 1
        }
        line = parse_decimal(bytes, a, colon)
        b := colon + 1
        colon2 := b
        while colon2 < len(bytes) and bytes[colon2] != 58 {
            colon2 = colon2 + 1
        }
        column = parse_decimal(bytes, b, colon2)
        if line == 0 or column == 0 {
            return nil
        }
    }
    path_bytes := bytes[0:path_end] @catch err {
        return err
    }
    path := owned_bytes(path_bytes) @catch err {
        return err
    }
    label_bytes := lists::create<u8>()
    defer lists::free<u8>(&label_bytes)
    lists::append_slice<u8>(&label_bytes, path_bytes) @catch err {
        strings::free(&path)
        return err
    }
    if p.kind == 2 {
        lists::append<u8>(&label_bytes, 58) @catch err {
            strings::free(&path)
            return err
        }
        tail := bytes[path_end + 1:len(bytes)] @catch err {
            strings::free(&path)
            return err
        }
        lists::append_slice<u8>(&label_bytes, tail) @catch err {
            strings::free(&path)
            return err
        }
    }
    label := owned_bytes(lists::view<u8>(&label_bytes)) @catch err {
        strings::free(&path)
        return err
    }
    item := Item{path: path, label: label, line: line, column: column}
    lists::append<Item>(&p.items, item) @catch err {
        strings::free(&path)
        strings::free(&label)
        return err
    }
    return nil
}

fn poll_picker(p *Picker) error {
    p.changed = false
    if p.running == false {
        return nil
    }
    chunk := zero<u8[8192]>()
    count, status := poll_search(&p.process, chunk[:])
    before := lists::count<Item>(&p.items)
    incoming := chunk[0:count] @catch err {
        return err
    }
    lists::append_slice<u8>(&p.pending, incoming) @catch err {
        return err
    }
    bytes := lists::view<u8>(&p.pending)
    start u64 := 0
    i u64 := 0
    path_seen := false
    while i < len(bytes) {
        delimiter := bytes[i] == 0
        if p.kind == 2 {
            if bytes[i] == 0 {
                path_seen = true
            }
            delimiter = bytes[i] == 10 and path_seen
        }
        if delimiter {
            record := bytes[start:i] @catch err {
                return err
            }
            add_record(p, record) @catch err {
                return err
            }
            start = i + 1
            path_seen = false
            if lists::count<Item>(&p.items) >= 50000 {
                p.limited = true
                break
            }
        }
        i = i + 1
    }
    remaining := len(bytes) - start
    j u64 := 0
    while j < remaining {
        bytes[j] = bytes[start + j]
        j = j + 1
    }
    while lists::count<u8>(&p.pending) > remaining {
        lists::pop<u8>(&p.pending)
    }
    if status != 0 or p.limited or remaining > 1048576 {
        p.changed = true
        p.failed = status < 0
        process::close_child(&p.process) @try
        p.running = false
    }
    if lists::count<Item>(&p.items) != before {
        p.changed = true
        return filter_picker(p)
    }
    return nil
}

fn picker_changed(p *Picker) error {
    p.selected = 0
    if p.kind == 2 {
        return restart_picker(p)
    }
    return filter_picker(p)
}

fn accept_picker(app *App) error {
    p := &app.picker
    matches := lists::view<Match>(&p.matches)
    if len(matches) == 0 {
        return nil
    }
    items := lists::view<Item>(&p.items)
    selected := &matches[p.selected]
    item := &items[selected.index]
    if p.kind == 3 {
        switch_buffer(app, item.buffer) @catch err {
            return err
        }
    } else {
        open_buffer(app, strings::view(&item.path)) @catch err {
            return err
        }
        if item.line > 0 and app.opened {
            b := buffer(app)
            start := rope::line_start(&b.text, item.line - 1)
            app.active.cursor = min(start + item.column - 1, line_end(&b.text, start))
        }
    }
    close_picker(p)
    return nil
}
