package editor

use "std::lists"
use "std::strings"
use "pkg::rope"
use "std::memory"
use "vendor::platform"

struct Replacement {
    file u64
    start u64
    end u64
    after lists::List<u8>
    selected bool
}

struct ReplaceFile {
    path strings::Owned
    label strings::Owned
    text rope::Rope
    buffer u64
    revision u64
    stamp u64
    chosen bool
}

struct ReplacePanel {
    open bool
    field bool
    query lists::List<u8>
    replacement lists::List<u8>
    hits lists::List<Replacement>
    selected u64
    regex bool
    sensitive bool
    word bool
    failed bool
    project bool
    hidden bool
    ignored bool
    ready bool
    reviewing bool
    scan_at u64
    files lists::List<ReplaceFile>
    discovery Picker
    report strings::Owned
}

fn clear_replacements(p *ReplacePanel) {
    hits := lists::view<Replacement>(&p.hits)
    i u64 := 0
    while i < len(hits) {
        lists::free<u8>(&hits[i].after)
        i = i + 1
    }
    lists::clear<Replacement>(&p.hits)
    files := lists::view<ReplaceFile>(&p.files)
    i = 0
    while i < len(files) {
        strings::free(&files[i].path)
        strings::free(&files[i].label)
        rope::free(&files[i].text)
        i = i + 1
    }
    lists::clear<ReplaceFile>(&p.files)
    p.ready = false
}

fn free_replace(p *ReplacePanel) {
    clear_replacements(p)
    p.failed = false
    lists::free<Replacement>(&p.hits)
    lists::free<ReplaceFile>(&p.files)
    close_picker(&p.discovery)
    lists::free<u8>(&p.query)
    lists::free<u8>(&p.replacement)
    strings::free(&p.report)
}

fn collect_replacements(app *App, file u64) error {
    p := &app.replace
    q := lists::view<u8>(&p.query)
    if len(q) == 0 {
        return nil
    }
    files := lists::view<ReplaceFile>(&p.files)
    b := &files[file]
    matcher rawptr := nil
    if platform::match_open(slice_data<u8>(q), len(q), p.regex, p.sensitive, p.word, &matcher) != 0 {
        p.failed = true
        app.message = "Invalid regex or query"
        return nil
    }
    defer platform::match_close(matcher)
    replacement := lists::view<u8>(&p.replacement)
    line u64 := 0
    while line <= rope::breaks(b.text.root) {
        base := rope::line_start(&b.text, line)
        bytes := rope::copy(&b.text, base, line_end(&b.text, base)) @try
        defer lists::free<u8>(&bytes)
        text := lists::view<u8>(&bytes)
        at u64 := 0
        while at <= len(text) {
            start u64 := 0
            end u64 := 0
            after rawptr := nil
            length u64 := 0
            status := platform::match_next(matcher, slice_data<u8>(text), len(text), at, slice_data<u8>(replacement), len(replacement), &start, &end, &after, &length)
            defer memory::free(after)
            if status < 0 {
                p.failed = true
                app.message = "Invalid replacement or regex limit exceeded"
                clear_replacements(p)
                return nil
            }
            if status == 0 {
                break
            }
            if lists::count<Replacement>(&p.hits) >= 50000 {
                p.failed = true
                app.message = "Too many matches (50,000 limit); narrow the query"
                return nil
            }
            hit := Replacement{file: file, start: base + start, end: base + end, selected: true}
            defer lists::free<u8>(&hit.after)
            lists::append_slice<u8>(&hit.after, slice_from_raw<u8>(after, length)) @try
            lists::append<Replacement>(&p.hits, hit) @try
            memory::take<lists::List<u8>>(&hit.after)
            at = end
            if start == end {
                if end == len(text) {
                    break
                }
                at = next_point(&b.text, base + end) - base
            }
        }
        line = line + 1
    }
    return nil
}

fn replacement_buffer(app *App, path string) u64 {
    buffers := lists::view<*Buffer>(&app.buffers)
    i u64 := 0
    while i < len(buffers) {
        if path != "" and strings::view(&buffers[i].path) == path {
            return i
        }
        i = i + 1
    }
    return 18446744073709551615
}

fn add_replace_file(app *App, path string, id u64, label string) error {
    p := &app.replace
    files := lists::view<ReplaceFile>(&p.files)
    for f in files {
        if path != "" and strings::view(&f.path) == path {
            return nil
        }
    }
    f := ReplaceFile{buffer: id}
    defer strings::free(&f.path)
    defer strings::free(&f.label)
    defer rope::free(&f.text)
    f.path = strings::clone(path) @try
    f.label = strings::clone(label) @try
    if path != "" {
        c := strings::to_c(path) @try
        defer strings::free_c(&c)
        f.stamp = platform::stamp(strings::c_view(&c))
    }
    if id != 18446744073709551615 {
        buffers := lists::view<*Buffer>(&app.buffers)
        b := buffers[id]
        f.revision = b.revision
        bytes := rope::copy(&b.text, 0, rope::size(b.text.root)) @try
        defer lists::free<u8>(&bytes)
        rope::replace(&f.text, 0, 0, lists::view<u8>(&bytes)) @try
    } else {
        c := strings::to_c(path) @try
        defer strings::free_c(&c)
        data rawptr := nil
        length u64 := 0
        status := platform::load(strings::c_view(&c), &data, &length)
        defer memory::free(data)
        if status != 0 {
            p.failed = true
            app.message = "Cannot read a project file; review blocked"
            return nil
        }
        bytes := slice_from_raw<u8>(data, length)
        for byte in bytes {
            if byte == 0 {
                return nil
            }
        }
        rope::replace(&f.text, 0, 0, bytes) @try
    }
    file := lists::count<ReplaceFile>(&p.files)
    lists::append<ReplaceFile>(&p.files, f) @try
    memory::take<strings::Owned>(&f.path)
    memory::take<strings::Owned>(&f.label)
    memory::take<rope::Rope>(&f.text)
    before := lists::count<Replacement>(&p.hits)
    collect_replacements(app, file) @try
    if p.failed == false and lists::count<Replacement>(&p.hits) == before {
        unused, found := lists::pop<ReplaceFile>(&p.files)
        strings::free(&unused.path)
        strings::free(&unused.label)
        rope::free(&unused.text)
    }
    return nil
}

fn refresh_replace(app *App) error {
    p := &app.replace
    close_picker(&p.discovery)
    p.reviewing = false
    clear_replacements(p)
    p.failed = false
    p.selected = 0
    app.message = ""
    if p.project {
        app.message = "Ctrl-g: review project replacements"
        return nil
    }
    b := buffer(app)
    parts := strings::split(strings::view(&b.path), "/") @try
    defer lists::free<string>(&parts)
    names := lists::view<string>(&parts)
    label := "[No Name]"
    if len(names) > 0 and strings::view(&b.path) != "" {
        label = names[len(names) - 1]
    }
    add_replace_file(app, strings::view(&b.path), app.active.buffer, label) @try
    p.ready = p.failed == false
    return nil
}

fn review_replace(app *App) error {
    p := &app.replace
    refresh_replace(app) @try
    if p.project {
        p.discovery.kind = 1
        p.discovery.hidden = p.hidden
        p.discovery.ignored = p.ignored
        restart_picker(&p.discovery) @try
        p.scan_at = 0
        p.reviewing = true
        app.message = "Discovering project files..."
    }
    return nil
}

fn poll_replace(app *App) error {
    p := &app.replace
    if p.reviewing == false {
        return nil
    }
    poll_picker(&p.discovery) @try
    if p.discovery.process != nil {
        return nil
    }
    if p.discovery.failed or p.discovery.limited {
        p.reviewing = false
        p.failed = true
        app.message = "File discovery failed or reached its limit; review blocked"
        return nil
    }
    items := lists::view<Item>(&p.discovery.items)
    stop := min(p.scan_at + 8, len(items))
    while p.scan_at < stop {
        item := &items[p.scan_at]
        p.scan_at = p.scan_at + 1
        c := strings::to_c(strings::view(&item.path)) @try
        defer strings::free_c(&c)
        resolved rawptr := nil
        status := platform::path(strings::c_view(&c), &resolved)
        defer memory::free(resolved)
        if status != 0 {
            p.failed = true
            app.message = "Project file disappeared; refresh review"
            break
        }
        path := strings::clone(strings::from_c(platform::cview(resolved))) @try
        defer strings::free(&path)
        name := strings::view(&path)
        add_replace_file(app, name, replacement_buffer(app, name), strings::view(&item.path)) @try
        if p.failed {
            break
        }
    }
    if p.failed == false and p.scan_at < len(items) {
        app.message = "Reviewing project files..."
        return nil
    }
    p.reviewing = false
    p.ready = p.failed == false
    if p.ready {
        app.message = "Review matches; Ctrl-a Apply selected (does not save)"
    }
    return nil
}

fn start_replace(app *App, project bool) error {
    app.mode = 0
    close_picker(&app.picker)
    app.replace.project = project
    app.replace.open = true
    app.replace.field = false
    return refresh_replace(app)
}

fn same_replace_text(a *rope::Rope, b *rope::Rope) bool {
    size := rope::size(a.root)
    if size != rope::size(b.root) {
        return false
    }
    i u64 := 0
    while i < size {
        if rope::byte(a, i) != rope::byte(b, i) {
            return false
        }
        i = i + 1
    }
    return true
}

fn replacement_current(app *App, f *ReplaceFile) (bool, error) {
    if strings::view(&f.path) != "" {
        c := strings::to_c(strings::view(&f.path)) @try
        defer strings::free_c(&c)
        if platform::stamp(strings::c_view(&c)) != f.stamp {
            return false, nil
        }
    }
    id := replacement_buffer(app, strings::view(&f.path))
    if f.buffer != 18446744073709551615 {
        id = f.buffer
    }
    if id != 18446744073709551615 {
        buffers := lists::view<*Buffer>(&app.buffers)
        b := buffers[id]
        return b.revision == f.revision and same_replace_text(&b.text, &f.text), nil
    }
    c := strings::to_c(strings::view(&f.path)) @try
    defer strings::free_c(&c)
    data rawptr := nil
    length u64 := 0
    status := platform::load(strings::c_view(&c), &data, &length)
    defer memory::free(data)
    if status != 0 or length != rope::size(f.text.root) {
        return false, nil
    }
    bytes := slice_from_raw<u8>(data, length)
    i u64 := 0
    while i < length {
        if bytes[i] != rope::byte(&f.text, i) {
            return false, nil
        }
        i = i + 1
    }
    return true, nil
}

fn apply_replacements(app *App, single bool) error {
    p := &app.replace
    if p.ready == false or p.failed {
        app.message = "Refresh review with Ctrl-g before applying"
        return nil
    }
    files := lists::view<ReplaceFile>(&p.files)
    hits := lists::view<Replacement>(&p.hits)
    i u64 := 0
    while i < len(files) {
        files[i].chosen = false
        i = i + 1
    }
    i = 0
    while i < len(hits) {
        if hits[i].selected and (single == false or i == p.selected) {
            files[hits[i].file].chosen = true
        }
        i = i + 1
    }
    i = 0
    while i < len(files) {
        if files[i].chosen {
            current := replacement_current(app, &files[i]) @try
            if current == false {
                p.ready = false
                app.message = "Text changed since review; refresh with Ctrl-g"
                return nil
            }
        }
        i = i + 1
    }
    original := app.active.buffer
    i = 0
    while i < len(files) {
        f := &files[i]
        if f.chosen and f.buffer == 18446744073709551615 {
            open_buffer(app, strings::view(&f.path)) @try
            f.buffer = replacement_buffer(app, strings::view(&f.path))
            if f.buffer == 18446744073709551615 {
                p.ready = false
                app.message = "Cannot open replacement target; nothing applied"
                switch_buffer(app, original) @try
                return nil
            }
            current := replacement_current(app, f) @try
            if current == false {
                p.ready = false
                app.message = "Text changed since review; refresh with Ctrl-g"
                switch_buffer(app, original) @try
                return nil
            }
        }
        i = i + 1
    }
    switch_buffer(app, original) @try
    app.group = app.group + 1
    changed u64 := 0
    affected u64 := 0
    for f in files {
        if f.chosen {
            affected = affected + 1
        }
    }
    i = len(hits)
    while i > 0 {
        i = i - 1
        if hits[i].selected and (single == false or i == p.selected) {
            f := &files[hits[i].file]
            splice_buffer(app, f.buffer, hits[i].start, hits[i].end, lists::view<u8>(&hits[i].after), false) @try
            changed = changed + 1
        }
    }
    app.group = app.group + 1
    if p.project {
        p.ready = false
    } else {
        refresh_replace(app) @try
    }
    summary := lists::create<u8>()
    defer lists::free<u8>(&summary)
    number(&summary, changed) @try
    if changed == 1 {
        append_text(&summary, " replacement in ") @try
    } else {
        append_text(&summary, " replacements in ") @try
    }
    number(&summary, affected) @try
    if affected == 1 {
        append_text(&summary, " buffer; unsaved") @try
    } else {
        append_text(&summary, " buffers; unsaved") @try
    }
    strings::free(&p.report)
    p.report = owned_bytes(lists::view<u8>(&summary)) @try
    app.message = strings::view(&p.report)
    return nil
}

fn replace_key(app *App, byte u8) error {
    p := &app.replace
    if byte == 9 {
        p.field = p.field == false
    } elif byte == 10 or byte == 11 {
        count := lists::count<Replacement>(&p.hits)
        if count > 0 {
            if byte == 10 {
                p.selected = p.selected + 1
                if p.selected == count {
                    p.selected = 0
                }
            } else {
                if p.selected == 0 {
                    p.selected = count
                }
                p.selected = p.selected - 1
            }
            if p.project == false {
                hits := lists::view<Replacement>(&p.hits)
                app.active.cursor = hits[p.selected].start
            }
        }
    } elif byte == 24 or byte == 6 {
        hits := lists::view<Replacement>(&p.hits)
        if p.selected < len(hits) {
            selected := hits[p.selected].selected == false
            file := hits[p.selected].file
            i u64 := 0
            while i < len(hits) {
                if (byte == 24 and i == p.selected) or (byte == 6 and hits[i].file == file) {
                    hits[i].selected = selected
                }
                i = i + 1
            }
        }
    } elif byte == 18 or byte == 20 or byte == 23 {
        if byte == 18 {
            p.regex = p.regex == false
        } elif byte == 20 {
            p.sensitive = p.sensitive == false
        } else {
            p.word = p.word == false
        }
        return refresh_replace(app)
    } elif byte == 19 or byte == 8 or byte == 15 {
        if byte == 19 {
            p.project = p.project == false
        } elif byte == 8 {
            p.hidden = p.hidden == false
        } else {
            p.ignored = p.ignored == false
        }
        return refresh_replace(app)
    } elif byte == 7 or byte == 13 {
        return review_replace(app)
    } elif byte == 1 or byte == 25 {
        return apply_replacements(app, byte == 25)
    } elif byte == 127 or byte >= 32 {
        field := &p.query
        if p.field {
            field = &p.replacement
        }
        if byte == 127 {
            pop_point(field)
        } else {
            lists::append<u8>(field, byte) @try
        }
        return refresh_replace(app)
    }
    return nil
}

fn replacement_display(bytes u8[]) (strings::Owned, error) {
    visible := lists::create<u8>()
    defer lists::free<u8>(&visible)
    for byte in bytes {
        if byte == 10 {
            append_text(&visible, "\\n") @try
        } elif byte == 9 {
            append_text(&visible, "\\t") @try
        } elif byte == 13 {
            append_text(&visible, "\\r") @try
        } elif byte == 0 {
            append_text(&visible, "\\0") @try
        } else {
            lists::append<u8>(&visible, byte) @try
        }
    }
    return owned_bytes(lists::view<u8>(&visible))
}

fn replacement_field_column(text string) (u64, error) {
    bytes := text_bytes(text) @try
    defer lists::free<u8>(&bytes)
    temp := zero<rope::Rope>()
    defer rope::free(&temp)
    rope::replace(&temp, 0, 0, lists::view<u8>(&bytes)) @try
    return display_column(&temp, 0, rope::size(temp.root)), nil
}

fn draw_replace(app *App, width u64, height u64) error {
    p := &app.replace
    if width < 40 or height < 12 {
        position(app, 0, height - 1) @try
        label(&app.frame, "Resize to 40x12; Esc close", width) @try
        app.cursor_visible = false
        return nil
    }
    top := height / 2
    position(app, 0, top) @try
    title := lists::create<u8>()
    defer lists::free<u8>(&title)
    append_text(&title, "REPLACE Buffer") @try
    if p.project {
        lists::clear<u8>(&title)
        append_text(&title, "REPLACE Project") @try
    }
    append_text(&title, " | ") @try
    number(&title, lists::count<Replacement>(&p.hits)) @try
    append_text(&title, " matches | ") @try
    if p.regex {
        append_text(&title, "Regex") @try
    } else {
        append_text(&title, "Literal") @try
    }
    if p.sensitive {
        append_text(&title, " Case-sensitive") @try
    }
    if p.word {
        append_text(&title, " Whole-word") @try
    }
    if p.hidden {
        append_text(&title, " Hidden") @try
    }
    if p.ignored {
        append_text(&title, " Ignored") @try
    }
    text := owned_bytes(lists::view<u8>(&title)) @try
    defer strings::free(&text)
    label(&app.frame, strings::view(&text), width) @try
    position(app, 0, top + 1) @try
    append_text(&app.frame, "Find: ") @try
    q := replacement_display(lists::view<u8>(&p.query)) @try
    defer strings::free(&q)
    label(&app.frame, strings::view(&q), width - 6) @try
    position(app, 0, top + 2) @try
    append_text(&app.frame, "With: ") @try
    r := replacement_display(lists::view<u8>(&p.replacement)) @try
    defer strings::free(&r)
    label(&app.frame, strings::view(&r), width - 6) @try
    position(app, 0, top + 3) @try
    label(&app.frame, "Tab field | ^s scope ^r regex ^t case ^w word | ^g Review | ^a Apply selected | ^y Replace", width) @try
    hits := lists::view<Replacement>(&p.hits)
    files := lists::view<ReplaceFile>(&p.files)
    rows := height - top - 6
    first u64 := 0
    if p.selected >= rows and rows > 0 {
        first = p.selected - rows + 1
    }
    row u64 := 0
    while row < rows {
        position(app, 0, top + 4 + row) @try
        index := first + row
        if index < len(hits) {
            hit := &hits[index]
            f := &files[hit.file]
            prefix := lists::create<u8>()
            defer lists::free<u8>(&prefix)
            if index == p.selected {
                append_text(&prefix, "> ") @try
            } else {
                append_text(&prefix, "  ") @try
            }
            if hit.selected {
                append_text(&prefix, "[x] ") @try
            } else {
                append_text(&prefix, "[ ] ") @try
            }
            name := strings::view(&f.label)
            if name == "" {
                name = "[No Name]"
            }
            append_text(&prefix, name) @try
            append_text(&prefix, ":") @try
            line := rope::line_at(&f.text, hit.start)
            number(&prefix, line + 1) @try
            append_text(&prefix, ":") @try
            number(&prefix, hit.start - rope::line_start(&f.text, line) + 1) @try
            prefix_text := owned_bytes(lists::view<u8>(&prefix)) @try
            defer strings::free(&prefix_text)
            label(&app.frame, strings::view(&prefix_text), width / 2) @try
            old := rope::copy(&f.text, hit.start, hit.end) @try
            defer lists::free<u8>(&old)
            old_text := replacement_display(lists::view<u8>(&old)) @try
            defer strings::free(&old_text)
            csi(&app.frame, "7m") @try
            label(&app.frame, strings::view(&old_text), width / 5) @try
            csi(&app.frame, "0m") @try
            append_text(&app.frame, " -> ") @try
            after := replacement_display(lists::view<u8>(&hit.after)) @try
            defer strings::free(&after)
            label(&app.frame, strings::view(&after), width - width / 2 - width / 5 - 4) @try
        } else {
            spaces(&app.frame, width) @try
        }
        row = row + 1
    }
    position(app, 0, height - 2) @try
    label(&app.frame, "^j/k next/previous | ^x select match ^f select file | ^h hidden ^o ignored | Esc cancel", width) @try
    app.cursor_y = top + 1
    column := replacement_field_column(strings::view(&q)) @try
    app.cursor_x = min(6 + column, width - 1)
    if p.field {
        app.cursor_y = top + 2
        column = replacement_field_column(strings::view(&r)) @try
        app.cursor_x = min(6 + column, width - 1)
    }
    app.cursor_visible = true
    return nil
}
