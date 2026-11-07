package editor

use "pkg::rope"
use "std::lists"
use "std::strings"
use "std::memory"
use "std::fs"
use "std::errors"

struct Edit {
    start u64
    before lists::List<u8>
    after lists::List<u8>
    previous u64
    revision u64
    group u64
}

struct Buffer {
    stamp fs::Metadata
    exists bool
    text rope::Rope
    path strings::Owned
    history lists::List<Edit>
    history_at u64
    revision u64
    saved u64
    serial u64
}

struct Pane {
    positions lists::List<Position>
    parent *Pane
    first *Pane
    second *Pane
    vertical bool
    ratio u64
    buffer u64
    previous u64
    cursor u64
    top u64
    left u64
    x u64
    y u64
    width u64
    height u64
}

struct Position {
    buffer u64
    cursor u64
    top u64
    left u64
}

struct App {
    config Config
    config_line u64
    mapping_input lists::List<u8>
    mapping_mode MappingMode
    mapping_deadline u64
    buffers lists::List<*Buffer>
    root *Pane
    active *Pane
    clipboard lists::List<u8>
    register_kind RegisterKind
    block_width u64
    mode Mode
    visual_anchor u64
    visual_column u64
    visual_wanted u64
    visual_anchor_column u64
    visual_eol bool
    block_insert bool
    block_insert_start u64
    block_insert_column u64
    block_insert_eol bool
    block_insert_rows lists::List<u64>
    pending u8
    count u64
    operator_count u64
    text_object u8
    character_find CharacterFind
    last_character_find CharacterFind
    group u64
    prompt lists::List<u8>
    last_change Change
    change Change
    change_active bool
    change_edited bool
    repeating bool
    repeat_group u64
    search lists::List<u8>
    search_mode Mode
    message string
    quit bool
    opened bool
    picker Picker
    input lists::List<u8>
    input_at u64
    paste bool
    paste_data lists::List<u8>
    frame lists::List<u8>
    rows lists::List<RenderRow>
    render_y u64
    render_x u64
    screen_width u64
    screen_height u64
    cursor_x u64
    cursor_y u64
    cursor_visible bool
    last_cursor_x u64
    last_cursor_y u64
    cursor_shown bool
    cursor_known bool
    sync_updates bool
}

fn buffer(app *App) *Buffer {
    items := lists::view<*Buffer>(&app.buffers)
    return items[app.active.buffer]
}

fn new_pane() (*Pane, error) {
    data := memory::alloc(sizeof<Pane>()) @try
    values := slice_from_raw<Pane>(data, 1)
    values[0] = zero<Pane>()
    return &values[0], nil
}

fn free_pane(p *Pane) {
    if p == nil {
        return
    }
    free_pane(p.first)
    free_pane(p.second)
    lists::free<Position>(&p.positions)
    memory::free(p)
}

fn free_edit(e *Edit) {
    lists::free<u8>(&e.before)
    lists::free<u8>(&e.after)
}

fn free_buffer(b *Buffer) {
    if b == nil {
        return
    }
    edits := lists::view<Edit>(&b.history)
    i u64 := 0
    while i < len(edits) {
        free_edit(&edits[i])
        i = i + 1
    }
    lists::free<Edit>(&b.history)
    rope::free(&b.text)
    strings::free(&b.path)
    memory::free(b)
}

fn free_app(app *App) {
    lists::free<ChangeInput>(&app.last_change.input)
    lists::free<ChangeInput>(&app.change.input)
    free_config(&app.config)
    lists::free<u8>(&app.mapping_input)
    close_picker(&app.picker)
    items := lists::view<*Buffer>(&app.buffers)
    for b in items {
        free_buffer(b)
    }
    lists::free<*Buffer>(&app.buffers)
    free_pane(app.root)
    lists::free<u8>(&app.clipboard)
    lists::free<u64>(&app.block_insert_rows)
    lists::free<u8>(&app.prompt)
    lists::free<u8>(&app.search)
    lists::free<u8>(&app.input)
    lists::free<u8>(&app.paste_data)
    lists::free<u8>(&app.frame)
    rows := lists::view<RenderRow>(&app.rows)
    i u64 := 0
    while i < len(rows) {
        row := &rows[i]
        free_row(row)
        i = i + 1
    }
    lists::free<RenderRow>(&app.rows)
}

fn open_buffer(app *App, path string) error {
    app.opened = false
    resolved, path_error := canonical(path)
    if path_error != nil {
        app.message = "Cannot resolve file path"
        return nil
    }
    defer strings::free(&resolved)
    name := strings::view(&resolved)
    items := lists::view<*Buffer>(&app.buffers)
    i u64 := 0
    while i < len(items) {
        if strings::view(&items[i].path) == name {
            app.opened = true
            return switch_buffer(app, i)
        }
        i = i + 1
    }
    data := strings::Owned{}
    defer strings::free(&data)
    info := fs::Metadata{}
    exists := false
    if name != "" {
        metadata, stat_err := fs::stat(name)
        if stat_err != nil and stat_err.kind != errors::Error::NotFound {
            app.message = "Cannot open file"
            return nil
        }
        exists = stat_err == nil
        info = metadata
        if exists {
            if info.kind != fs::FileType::Regular {
                app.message = "Cannot open file"
                return nil
            }
            loaded := fs::read_file(name) @catch err {
                app.message = "Cannot open file"
                return nil
            }
            data = memory::take<strings::Owned>(&loaded)
        }
    }
    storage := memory::alloc(sizeof<Buffer>()) @try
    values := slice_from_raw<Buffer>(storage, 1)
    values[0] = zero<Buffer>()
    b := &values[0]
    defer free_buffer(b)
    b.stamp = info
    b.exists = exists
    b.path = strings::clone(name) @try
    bytes := strings::to_bytes(strings::view(&data)) @try
    defer lists::free<u8>(&bytes)
    rope::replace(&b.text, 0, 0, lists::view<u8>(&bytes)) @try
    lists::append<*Buffer>(&app.buffers, b) @try
    memory::take<*Buffer>(&b)
    app.message = ""
    app.opened = true
    return switch_buffer(app, lists::count<*Buffer>(&app.buffers) - 1)
}

fn save_buffer(app *App, path string) error {
    b := buffer(app)
    name := path
    if name == "" {
        name = strings::view(&b.path)
    }
    if name == "" {
        app.message = "Use :w path to name this buffer"
        return nil
    }
    new_name := canonical(name) @catch err {
        app.message = "Cannot resolve save destination"
        return nil
    }
    defer strings::free(&new_name)
    name = strings::view(&new_name)
    buffers := lists::view<*Buffer>(&app.buffers)
    for other in buffers {
        if other != b and strings::view(&other.path) == name {
            app.message = "Destination is already open in another buffer"
            return nil
        }
    }
    current_stamp, stat_err := fs::stat(name)
    if stat_err != nil and stat_err.kind != errors::Error::NotFound {
        app.message = "Cannot inspect save destination"
        return nil
    }
    exists := stat_err == nil
    same := name == strings::view(&b.path)
    changed := exists != b.exists
    if exists and b.exists {
        changed = fs::same_file(current_stamp, b.stamp) == false or current_stamp.size != b.stamp.size or current_stamp.modified_seconds != b.stamp.modified_seconds or current_stamp.modified_nanoseconds != b.stamp.modified_nanoseconds
    }
    if (same and changed) or (same == false and exists) {
        app.message = "Save refused: file changed on disk or destination already exists"
        return nil
    }
    bytes := rope::copy(&b.text, 0, rope::size(b.text.root)) @try
    defer lists::free<u8>(&bytes)
    contents := strings::from_bytes(lists::view<u8>(&bytes)) @try
    defer strings::free(&contents)
    replaced, save_err := fs::write_atomic(name, strings::view(&contents))
    if replaced == false {
        app.message = "Save failed; original file was not truncated"
        return nil
    }
    strings::free(&b.path)
    b.path = memory::take<strings::Owned>(&new_name)
    b.saved = b.revision
    updated, updated_err := fs::stat(name)
    b.stamp = updated
    b.exists = true
    app.message = "Written"
    if save_err != nil {
        app.message = "Written; directory synchronization failed"
    }
    if updated_err != nil {
        app.message = "Written; cannot refresh file metadata"
    }
    return nil
}

fn adjust(p *Pane, id u64, start u64, end u64, added u64) {
    if p.first != nil {
        adjust(p.first, id, start, end, added)
        adjust(p.second, id, start, end, added)
        return
    }
    if p.buffer != id {
        saved := lists::view<Position>(&p.positions)
        i u64 := 0
        while i < len(saved) {
            position := &saved[i]
            if position.buffer == id {
                position.cursor = adjusted_cursor(position.cursor, start, end, added)
            }
            i = i + 1
        }
    } else {
        p.cursor = adjusted_cursor(p.cursor, start, end, added)
    }
}

fn adjusted_cursor(cursor u64, start u64, end u64, added u64) u64 {
    if cursor >= end {
        return cursor - (end - start) + added
    }
    if cursor > start {
        return start + added
    }
    return cursor
}

fn edit(app *App, start u64, end u64, data u8[]) error {
    b := buffer(app)
    if start == end and len(data) == 0 {
        return nil
    }
    before := rope::copy(&b.text, start, end) @try
    defer lists::free<u8>(&before)
    after := lists::create<u8>()
    defer lists::free<u8>(&after)
    lists::append_slice<u8>(&after, data) @try
    lists::reserve<Edit>(&b.history, lists::count<Edit>(&b.history) + 1) @try
    rope::replace(&b.text, start, end, data) @try
    while lists::count<Edit>(&b.history) > b.history_at {
        old, found := lists::pop<Edit>(&b.history)
        free_edit(&old)
    }
    b.serial = b.serial + 1
    group := app.group
    if app.repeating {
        group = app.repeat_group
    }
    record := Edit{start: start, before: memory::take<lists::List<u8>>(&before), after: memory::take<lists::List<u8>>(&after), previous: b.revision, revision: b.serial, group: group}
    defer free_edit(&record)
    lists::append<Edit>(&b.history, record) @try
    memory::take<Edit>(&record)
    b.history_at = b.history_at + 1
    b.revision = b.serial
    if app.change_active {
        app.change_edited = true
    }
    adjust(app.root, app.active.buffer, start, end, len(data))
    app.active.cursor = start + len(data)
    return nil
}

fn undo(app *App, redo bool) error {
    b := buffer(app)
    records := lists::view<Edit>(&b.history)
    if redo {
        if b.history_at == len(records) {
            return nil
        }
        group := records[b.history_at].group
        while b.history_at < len(records) {
            e := &records[b.history_at]
            if e.group != group {
                break
            }
            end := e.start + lists::count<u8>(&e.before)
            rope::replace(&b.text, e.start, end, lists::view<u8>(&e.after)) @try
            adjust(app.root, app.active.buffer, e.start, end, lists::count<u8>(&e.after))
            app.active.cursor = e.start + lists::count<u8>(&e.after)
            b.revision = e.revision
            b.history_at = b.history_at + 1
        }
    } else {
        if b.history_at == 0 {
            return nil
        }
        undo_group := records[b.history_at - 1].group
        while b.history_at > 0 {
            e2 := &records[b.history_at - 1]
            if e2.group != undo_group {
                break
            }
            end2 := e2.start + lists::count<u8>(&e2.after)
            rope::replace(&b.text, e2.start, end2, lists::view<u8>(&e2.before)) @try
            adjust(app.root, app.active.buffer, e2.start, end2, lists::count<u8>(&e2.before))
            app.active.cursor = e2.start
            b.revision = e2.previous
            b.history_at = b.history_at - 1
        }
    }
    return nil
}

fn previous_point(r *rope::Rope, at u64) u64 {
    if at == 0 {
        return 0
    }
    pos := at - 1
    while pos > 0 and rope::byte(r, pos) >= Utf8ContinuationFirst and rope::byte(r, pos) < Utf8ContinuationLimit {
        pos = pos - 1
    }
    return pos
}

fn next_point(r *rope::Rope, at u64) u64 {
    pos := min(at + 1, rope::size(r.root))
    while pos < rope::size(r.root) and rope::byte(r, pos) >= Utf8ContinuationFirst and rope::byte(r, pos) < Utf8ContinuationLimit {
        pos = pos + 1
    }
    return pos
}

fn line_end(r *rope::Rope, at u64) u64 {
    line := rope::line_at(r, at)
    if line >= rope::breaks(r.root) {
        return rope::size(r.root)
    }
    return rope::line_start(r, line + 1) - 1
}

fn insert_newline(app *App, at u64) error {
    b := buffer(app)
    start := rope::line_start(&b.text, rope::line_at(&b.text, at))
    end := indentation_end(&b.text, start, at)
    data := lists::create<u8>()
    defer lists::free<u8>(&data)
    lists::append<u8>(&data, ByteLF) @try
    indent := rope::copy(&b.text, start, end) @try
    defer lists::free<u8>(&indent)
    lists::append_slice<u8>(&data, lists::view<u8>(&indent)) @try
    return edit(app, at, at, lists::view<u8>(&data))
}

fn word_class(byte u8) u8 {
    if byte == ByteSpace or (byte >= ByteTab and byte <= ByteCR) {
        return 0
    }
    if (byte >= AsciiDigitFirst and byte <= AsciiDigitLast) or (byte >= AsciiUpperFirst and byte <= AsciiUpperLast) or (byte >= AsciiLowerFirst and byte <= AsciiLowerLast) or byte == ByteUnderscore or byte >= Utf8ContinuationFirst {
        return 1
    }
    return 2
}

fn move(app *App, key u8) {
    b := buffer(app)
    p := app.active
    line := rope::line_at(&b.text, p.cursor)
    start := rope::line_start(&b.text, line)
    if key == KeyLowerW {
        size := rope::size(b.text.root)
        if p.cursor >= size {
            return
        }
        kind := word_class(rope::byte(&b.text, p.cursor))
        if kind == 0 {
            p.cursor = next_point(&b.text, p.cursor)
        }
        while kind != 0 and p.cursor < size and word_class(rope::byte(&b.text, p.cursor)) == kind {
            p.cursor = next_point(&b.text, p.cursor)
        }
        while p.cursor < size and word_class(rope::byte(&b.text, p.cursor)) == 0 {
            if rope::byte(&b.text, p.cursor) == ByteLF and (p.cursor == 0 or rope::byte(&b.text, p.cursor - 1) == ByteLF) {
                break
            }
            p.cursor = next_point(&b.text, p.cursor)
        }
        if p.cursor == size and size > 0 {
            p.cursor = previous_point(&b.text, size)
        }
    }
    if key == KeyLowerB and p.cursor > 0 {
        p.cursor = previous_point(&b.text, p.cursor)
        while p.cursor > 0 and word_class(rope::byte(&b.text, p.cursor)) == 0 {
            if rope::byte(&b.text, p.cursor) == ByteLF and rope::byte(&b.text, p.cursor - 1) == ByteLF {
                break
            }
            p.cursor = previous_point(&b.text, p.cursor)
        }
        kind := word_class(rope::byte(&b.text, p.cursor))
        while kind != 0 and p.cursor > 0 {
            previous := previous_point(&b.text, p.cursor)
            if word_class(rope::byte(&b.text, previous)) != kind {
                break
            }
            p.cursor = previous
        }
    }
    if key == KeyLowerH and p.cursor > start {
        p.cursor = previous_point(&b.text, p.cursor)
    }
    if key == KeyLowerL and p.cursor < line_end(&b.text, p.cursor) {
        p.cursor = next_point(&b.text, p.cursor)
    }
    if key == KeyZero {
        p.cursor = start
    }
    if key == KeyDollar {
        p.cursor = line_end(&b.text, p.cursor)
    }
    if key == KeyUpperG {
        p.cursor = rope::line_start(&b.text, rope::breaks(b.text.root))
    }
    if key == KeyLowerJ or key == KeyLowerK {
        target := line
        if key == KeyLowerJ and line < rope::breaks(b.text.root) {
            target = line + 1
        }
        if key == KeyLowerK and line > 0 {
            target = line - 1
        }
        column u64 := 0
        at := start
        while at < p.cursor {
            at = next_point(&b.text, at)
            column = column + 1
        }
        p.cursor = rope::line_start(&b.text, target)
        last := line_end(&b.text, p.cursor)
        while column > 0 and p.cursor < last {
            p.cursor = next_point(&b.text, p.cursor)
            column = column - 1
        }
    }
}

fn split_pane(app *App, vertical bool) error {
    if (vertical and app.active.width < 12) or (vertical == false and app.active.height < 6) {
        app.message = "Pane is too small to split"
        return nil
    }
    a := new_pane() @catch err {
        return err
    }
    b, alloc_error := new_pane()
    if alloc_error != nil {
        memory::free(a)
        return alloc_error
    }
    p := app.active
    a.buffer = p.buffer
    a.previous = p.previous
    a.cursor = p.cursor
    a.top = p.top
    a.left = p.left
    a.positions = memory::take<lists::List<Position>>(&p.positions)
    b.buffer = p.buffer
    b.previous = p.previous
    b.cursor = p.cursor
    b.top = p.top
    b.left = p.left
    a.parent = p
    b.parent = p
    p.first = a
    p.second = b
    p.vertical = vertical
    p.ratio = 50
    app.active = b
    return nil
}

fn first_leaf(p *Pane) *Pane {
    current := p
    while current.first != nil {
        current = current.first
    }
    return current
}

fn dirty(app *App) bool {
    items := lists::view<*Buffer>(&app.buffers)
    for b in items {
        if b.revision != b.saved {
            return true
        }
    }
    return false
}

fn close_pane(app *App, force bool) {
    b := buffer(app)
    if force == false and b.revision != b.saved {
        app.message = "Unsaved changes; use :w or :q!"
        return
    }
    p := app.active
    if p.parent == nil {
        if force == false and dirty(app) {
            app.message = "Other buffers have unsaved changes; use :qa!"
            return
        }
        app.quit = true
        return
    }
    parent := p.parent
    sibling := parent.first
    if sibling == p {
        sibling = parent.second
    }
    grand := parent.parent
    parent.first = sibling.first
    parent.second = sibling.second
    parent.vertical = sibling.vertical
    parent.ratio = sibling.ratio
    parent.buffer = sibling.buffer
    parent.previous = sibling.previous
    parent.cursor = sibling.cursor
    parent.top = sibling.top
    parent.left = sibling.left
    parent.positions = memory::take<lists::List<Position>>(&sibling.positions)
    parent.parent = grand
    if parent.first != nil {
        parent.first.parent = parent
        parent.second.parent = parent
    }
    memory::free(sibling)
    lists::free<Position>(&p.positions)
    memory::free(p)
    app.active = first_leaf(parent)
}
