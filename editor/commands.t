package editor

use "std::lists"
use "std::strings"
use "std::memory"
use "pkg::rope"

fn switch_buffer(app *App, id u64) error {
    if id >= lists::count<*Buffer>(&app.buffers) {
        return nil
    }
    p := app.active
    if id == p.buffer {
        return nil
    }
    positions := lists::view<Position>(&p.positions)
    i u64 := 0
    saved := false
    while i < len(positions) {
        position := &positions[i]
        if position.buffer == p.buffer {
            position.cursor = p.cursor
            position.top = p.top
            position.left = p.left
            saved = true
        }
        i = i + 1
    }
    if saved == false {
        lists::append<Position>(&p.positions, Position{buffer: p.buffer, cursor: p.cursor, top: p.top, left: p.left}) @try
    }
    app.active.previous = app.active.buffer
    app.active.buffer = id
    app.active.cursor = 0
    app.active.top = 0
    app.active.left = 0
    restored := lists::view<Position>(&p.positions)
    j u64 := 0
    while j < len(restored) {
        old := &restored[j]
        if old.buffer == id {
            p.cursor = old.cursor
            p.top = old.top
            p.left = old.left
        }
        j = j + 1
    }
    return nil
}

fn equalize(p *Pane) {
    if p.first != nil {
        p.ratio = 50
        equalize(p.first)
        equalize(p.second)
    }
}

fn focus_candidate(p *Pane, current *Pane, direction u8, best **Pane, distance *u64) {
    if p.first != nil {
        focus_candidate(p.first, current, direction, best, distance)
        focus_candidate(p.second, current, direction, best, distance)
        return
    }
    if p == current or p.width == 0 or p.height == 0 {
        return
    }
    cx := current.x + current.width / 2
    cy := current.y + current.height / 2
    px := p.x + p.width / 2
    py := p.y + p.height / 2
    dx := cx
    dy := cy
    if px > cx {
        dx = px - cx
    } else {
        dx = cx - px
    }
    if py > cy {
        dy = py - cy
    } else {
        dy = cy - py
    }
    valid := (direction == KeyLowerH and px < cx) or (direction == KeyLowerL and px > cx) or (direction == KeyLowerJ and py > cy) or (direction == KeyLowerK and py < cy)
    score := dx + dy * 4
    if direction == KeyLowerH or direction == KeyLowerL {
        score = dx * 4 + dy
    }
    if valid and score < *distance {
        *distance = score
        *best = p
    }
}

fn window_key(app *App, key u8) error {
    if key == KeyLowerV {
        return split_pane(app, true)
    }
    if key == KeyLowerS {
        return split_pane(app, false)
    }
    if key == KeyLowerC {
        close_pane(app, false)
        return nil
    }
    if key == KeyEqual {
        equalize(app.root)
        return nil
    }
    if key == KeyLowerH or key == KeyLowerJ or key == KeyLowerK or key == KeyLowerL {
        best := app.active
        distance u64 := 18446744073709551615
        focus_candidate(app.root, app.active, key, &best, &distance)
        app.active = best
        return nil
    }
    if key == KeyPlus or key == KeyMinus or key == KeyGreater or key == KeyLess {
        p := app.active.parent
        vertical := key == KeyGreater or key == KeyLess
        while p != nil and p.vertical != vertical {
            p = p.parent
        }
        if p != nil {
            first := app.active
            while first.parent != p {
                first = first.parent
            }
            grow := key == KeyPlus or key == KeyGreater
            increase := grow == (first == p.first)
            if increase and p.ratio < 90 {
                p.ratio = p.ratio + 5
            }
            if increase == false and p.ratio > 10 {
                p.ratio = p.ratio - 5
            }
        }
    }
    return nil
}

fn find(app *App, reverse bool) {
    b := buffer(app)
    query := lists::view<u8>(&app.search)
    size := rope::size(b.text.root)
    if len(query) == 0 or len(query) > size {
        app.message = "No search match"
        return
    }
    sensitive := false
    for byte in query {
        if byte >= AsciiUpperFirst and byte <= AsciiUpperLast {
            sensitive = true
        }
    }
    offset := app.active.cursor
    tried u64 := 0
    while tried < size {
        if reverse {
            if offset == 0 {
                offset = size - 1
            } else {
                offset = offset - 1
            }
        } else {
            offset = offset + 1
            if offset >= size {
                offset = 0
            }
        }
        good := offset + len(query) <= size
        i u64 := 0
        while i < len(query) and good {
            left := rope::byte(&b.text, offset + i)
            right := query[i]
            if sensitive == false {
                left = fold(left)
                right = fold(right)
            }
            good = left == right
            i = i + 1
        }
        if good {
            app.active.cursor = offset
            return
        }
        tried = tried + 1
    }
    app.message = "No search match"
}

fn yank(app *App, start u64, end u64, linewise bool) error {
    b := buffer(app)
    copied := rope::copy(&b.text, start, end) @catch err {
        return err
    }
    lists::free<u8>(&app.clipboard)
    app.clipboard = copied
    app.register_kind = RegisterKind::Characterwise
    app.block_width = 0
    if linewise {
        app.register_kind = RegisterKind::Linewise
    }
    app.message = "Yanked"
    return nil
}

fn paste_clipboard(app *App) error {
    return paste_register(app, lists::view<u8>(&app.clipboard), app.register_kind, app.block_width)
}

fn paste_register(app *App, bytes u8[], kind RegisterKind, width u64) error {
    b := buffer(app)
    at := app.active.cursor
    if len(bytes) == 0 and kind == RegisterKind::Characterwise {
        return nil
    }
    if kind == RegisterKind::Blockwise {
        line := rope::line_at(&b.text, at)
        if at < line_end(&b.text, at) {
            at = next_point(&b.text, at)
        }
        return put_block(app, bytes, line, cursor_column(&b.text, at), width)
    }
    if kind == RegisterKind::Linewise {
        at = line_end(&b.text, at)
        if len(bytes) == 0 {
            if at < rope::size(b.text.root) {
                at = at + 1
            }
            newline u8[1] := .{ByteLF}
            return edit(app, at, at, newline[:])
        }
        if at < rope::size(b.text.root) {
            at = at + 1
            if bytes[len(bytes) - 1] != ByteLF {
                complete := lists::create<u8>()
                defer lists::free<u8>(&complete)
                lists::append_slice<u8>(&complete, bytes) @catch err {
                    return err
                }
                lists::append<u8>(&complete, ByteLF) @catch err {
                    return err
                }
                return edit(app, at, at, lists::view<u8>(&complete))
            }
        } else {
            insert := lists::create<u8>()
            defer lists::free<u8>(&insert)
            lists::append<u8>(&insert, ByteLF) @catch err {
                return err
            }
            lists::append_slice<u8>(&insert, bytes) @catch err {
                return err
            }
            if bytes[len(bytes) - 1] == ByteLF {
                lists::pop<u8>(&insert)
            }
            return edit(app, at, at, lists::view<u8>(&insert))
        }
    } else {
        if at < line_end(&b.text, at) {
            at = next_point(&b.text, at)
        }
    }
    return edit(app, at, at, bytes)
}

fn remap_panes(p *Pane, removed u64, fallback u64) {
    if p.first != nil {
        remap_panes(p.first, removed, fallback)
        remap_panes(p.second, removed, fallback)
        return
    }
    if p.buffer == removed {
        p.buffer = fallback
        p.cursor = 0
        p.top = 0
        p.left = 0
    } else {
        if p.buffer > removed {
            p.buffer = p.buffer - 1
        }
    }
    p.previous = p.buffer
    positions := lists::view<Position>(&p.positions)
    i u64 := 0
    while i < lists::count<Position>(&p.positions) {
        current_positions := lists::view<Position>(&p.positions)
        saved := &current_positions[i]
        if saved.buffer == removed {
            lists::remove<Position>(&p.positions, i)
        } else {
            if saved.buffer > removed {
                saved.buffer = saved.buffer - 1
            }
            i = i + 1
        }
    }
}

fn delete_buffer(app *App) {
    b := buffer(app)
    if b.revision != b.saved {
        app.message = "Unsaved changes; save before :bd"
        return
    }
    count := lists::count<*Buffer>(&app.buffers)
    if count <= 1 {
        app.message = "Cannot close the last buffer; use :q"
        return
    }
    id := app.active.buffer
    removed, remove_error := lists::remove<*Buffer>(&app.buffers, id)
    if remove_error != nil {
        return
    }
    free_buffer(removed)
    remap_panes(app.root, id, 0)
}

fn command(app *App) error {
    owned := owned_bytes(lists::view<u8>(&app.prompt)) @catch err {
        return err
    }
    defer strings::free(&owned)
    text := strings::view(&owned)
    space, has_space := strings::find(text, " ")
    name := text
    arg := ""
    if has_space {
        a := strings::slice(text, 0, space) @catch err {
            return err
        }
        name = a
        b := strings::slice(text, space + 1, strings::len(text)) @catch err {
            return err
        }
        arg = b
    }
    if name == "w" or name == "wq" {
        save_buffer(app, arg) @catch err {
            return err
        }
        if name == "wq" {
            current := buffer(app)
            if app.message == "Written" and current.revision == current.saved and strings::view(&current.path) != "" {
                close_pane(app, false)
            }
        }
    } elif name == "q" or name == "q!" {
        close_pane(app, name == "q!")
    } elif name == "qa" or name == "qa!" {
        if name == "qa!" or dirty(app) == false {
            app.quit = true
        } else {
            app.message = "Unsaved buffers; use :qa! to discard"
        }
    } elif name == "e" or name == "edit" {
        if arg != "" {
            return open_buffer(app, arg)
        }
    } elif name == "split" or name == "vsplit" {
        split_pane(app, name == "vsplit") @catch err {
            return err
        }
        if arg != "" {
            return open_buffer(app, arg)
        }
    } elif name == "files" {
        return start_picker(app, PickerKind::Files)
    } elif name == "grep" {
        start_picker(app, PickerKind::ProjectSearch) @catch err {
            return err
        }
        append_text(&app.picker.query, arg) @catch err {
            return err
        }
        return restart_picker(&app.picker)
    } elif name == "buffers" or name == "ls" {
        return start_picker(app, PickerKind::Buffers)
    } elif name == "bn" or name == "bnext" {
        id := app.active.buffer + 1
        if id >= lists::count<*Buffer>(&app.buffers) {
            id = 0
        }
        return switch_buffer(app, id)
    } elif name == "bp" or name == "bprevious" {
        id2 := app.active.buffer
        if id2 == 0 {
            id2 = lists::count<*Buffer>(&app.buffers)
        }
        return switch_buffer(app, id2 - 1)
    } elif name == "b#" {
        return switch_buffer(app, app.active.previous)
    } elif name == "bd" {
        delete_buffer(app)
    } elif name == "copy" {
        bytes := lists::view<u8>(&app.clipboard)
        copy_err := copy_clipboard(bytes)
        if copy_err == nil {
            app.message = "Yank register copied to macOS clipboard"
        } else {
            app.message = "pbcopy failed"
        }
    } elif name == "paste" {
        data, paste_err := read_system_clipboard()
        defer lists::free<u8>(&data)
        if paste_err == nil {
            return edit(app, app.active.cursor, app.active.cursor, lists::view<u8>(&data))
        }
        app.message = "pbpaste failed"
    } elif name == "help" {
        app.message = "v/V/Ctrl-v select | d/y/c/p selection | i/a/o insert | u Ctrl-r | :e/w/q/files/grep/buffers"
    } else {
        if name != "" {
            app.message = "Unknown command; see :help or README.md"
        }
    }
    return nil
}

fn pop_point(bytes *lists::List<u8>) {
    if lists::count<u8>(bytes) == 0 {
        return
    }
    b, found := lists::pop<u8>(bytes)
    while b >= Utf8ContinuationFirst and b < Utf8ContinuationLimit and lists::count<u8>(bytes) > 0 {
        previous, exists := lists::pop<u8>(bytes)
        b = previous
    }
}

fn builtin_key(app *App, byte u8) error {
    record_change_input(app, ChangeInputKind::Key, byte) @try
    dispatch_key(app, byte) @try
    if app.change_active and app.mode != Mode::Insert and app.character_find.motion == 0 {
        finish_change(app)
    }
    return nil
}

fn dispatch_key(app *App, byte u8) error {
    if byte == KeyEscape or byte == KeyCtrlC {
        if app.block_insert {
            if byte == KeyEscape {
                finish_block_insert(app) @try
            } else {
                cancel_block_insert(app)
            }
        }
        if app.picker.kind != PickerKind::None {
            close_picker(&app.picker)
        }
        app.mode = Mode::Normal
        app.pending = 0
        app.count = 0
        app.operator_count = 0
        app.text_object = 0
        app.character_find = zero<CharacterFind>()
        app.group = app.group + 1
        return nil
    }
    if app.picker.kind != PickerKind::None {
        p := &app.picker
        if byte == KeyEnter {
            return accept_picker(app)
        } elif byte == KeyCtrlJ or byte == KeyCtrlK {
            count := lists::count<Match>(&p.matches)
            if byte == KeyCtrlJ and p.selected + 1 < count {
                p.selected = p.selected + 1
            }
            if byte == KeyCtrlK and p.selected > 0 {
                p.selected = p.selected - 1
            }
        } elif byte == KeyBackspace and p.kind != PickerKind::Buffers {
            p.hidden = p.hidden == false
            return restart_picker(p)
        } elif byte == KeyCtrlR and p.kind == PickerKind::ProjectSearch {
            p.regex = p.regex == false
            return restart_picker(p)
        } elif byte == KeyTab and p.kind != PickerKind::Buffers {
            p.ignored = p.ignored == false
            return restart_picker(p)
        } elif byte == KeyDelete {
            pop_point(&p.query)
            return picker_changed(p)
        } elif byte >= ByteSpace {
            lists::append<u8>(&p.query, byte) @catch err {
                return err
            }
            return picker_changed(p)
        }
        return nil
    }
    if app.mode == Mode::Command or app.mode == Mode::Search {
        if byte == KeyEnter {
            mode := app.mode
            app.mode = Mode::Normal
            if mode == Mode::Command {
                app.group = app.group + 1
                return command(app)
            }
            if lists::count<u8>(&app.prompt) > 0 {
                lists::clear<u8>(&app.search)
                lists::append_slice<u8>(&app.search, lists::view<u8>(&app.prompt)) @catch err {
                    return err
                }
            }
            find(app, false)
            app.mode = app.search_mode
            app.search_mode = Mode::Normal
            if app.mode == Mode::VisualBlock {
                app.visual_column = cursor_column(&buffer(app).text, app.active.cursor)
                app.visual_wanted = app.visual_column
            }
        } elif byte == KeyDelete or byte == KeyBackspace {
            pop_point(&app.prompt)
        } elif byte >= ByteSpace {
            lists::append<u8>(&app.prompt, byte) @catch err {
                return err
            }
        }
        return nil
    }
    b := buffer(app)
    at := app.active.cursor
    if app.mode == Mode::Insert {
        if byte == KeyDelete or byte == KeyBackspace {
            if app.block_insert and at <= app.block_insert_start {
                cancel_block_insert(app)
            }
            if at > 0 {
                empty := zero<u8[]>()
                return edit(app, previous_point(&b.text, at), at, empty)
            }
        } elif byte == KeyEnter or byte == KeyCtrlJ {
            return insert_newline(app, at)
        } elif byte == KeyTab or byte >= ByteSpace {
            single u8[1] := .{byte}
            return edit(app, at, at, single[:])
        }
        return nil
    }
    app.message = ""
    if app.character_find.motion != 0 {
        return finish_character_find(app, byte)
    }
    if app.pending == KeyCtrlW {
        app.pending = 0
        app.count = 0
        app.operator_count = 0
        return window_key(app, byte)
    }
    if byte == KeyUpperV or byte == KeyLowerV or byte == KeyCtrlV {
        target := Mode::VisualCharacter
        if byte == KeyUpperV {
            target = Mode::VisualLine
        }
        if byte == KeyCtrlV {
            target = Mode::VisualBlock
        }
        if app.mode == target {
            app.mode = Mode::Normal
        } else {
            if visual(app) == false {
                app.visual_anchor = at
            }
            app.mode = target
            app.visual_column = cursor_column(&b.text, at)
            app.visual_wanted = app.visual_column
            app.visual_anchor_column = cursor_column(&b.text, app.visual_anchor)
            app.visual_eol = false
        }
        app.pending = 0
        app.count = 0
        app.operator_count = 0
        app.text_object = 0
        return nil
    }
    if visual(app) {
        return visual_key(app, byte)
    }
    if byte >= AsciiDigitFirst and byte <= AsciiDigitLast and (byte != KeyZero or app.count > 0) {
        digit := widen<u64>(byte - AsciiDigitFirst)
        if app.count <= (MaxCommandCount - digit) / 10 {
            app.count = app.count * 10 + digit
        } else {
            app.count = MaxCommandCount
        }
        return nil
    }
    if app.pending != 0 {
        previous := app.pending
        if (previous == KeyLowerD or previous == KeyLowerY or previous == KeyLowerC) and app.text_object == 0 and (byte == KeyLowerI or byte == KeyLowerA) {
            app.text_object = byte
            return nil
        }
        app.pending = 0
        repeats := max(1, app.count)
        if app.operator_count > MaxCommandCount / repeats {
            repeats = MaxCommandCount
        } else {
            repeats = repeats * max(1, app.operator_count)
        }
        app.count = 0
        app.operator_count = 0
        object := app.text_object
        app.text_object = 0
        if object != 0 {
            if byte == KeyLowerW {
                return operator_word_object(app, previous, object == KeyLowerA, repeats)
            }
            return nil
        }
        if previous == KeyLowerG and byte == KeyLowerG {
            app.active.cursor = rope::line_start(&b.text, min(repeats - 1, rope::breaks(b.text.root)))
        }
        if (previous == KeyLowerD or previous == KeyLowerY or previous == KeyLowerC) and byte == previous {
            return operator_lines(app, previous, repeats)
        }
        if previous == KeyLowerD or previous == KeyLowerY or previous == KeyLowerC {
            return operator_motion(app, previous, byte, repeats)
        }
        return nil
    }
    count := app.count
    app.count = 0
    if character_find_motion(byte) {
        app.character_find = CharacterFind{motion: byte, count: max(1, count)}
    } elif byte == KeySemicolon or byte == KeyComma {
        return repeat_character_find(app, byte == KeyComma, max(1, count), 0)
    } elif byte == KeyUpperG and count > 0 {
        app.active.cursor = rope::line_start(&b.text, min(count - 1, rope::breaks(b.text.root)))
    } elif byte == KeyDollar {
        line := rope::line_at(&b.text, at)
        target := line + min(max(1, count) - 1, rope::breaks(b.text.root) - line)
        app.active.cursor = line_end(&b.text, rope::line_start(&b.text, target))
    } elif byte == KeyLowerH or byte == KeyLowerJ or byte == KeyLowerK or byte == KeyLowerL or byte == KeyZero or byte == KeyUpperG or byte == KeyLowerW or byte == KeyLowerB {
        repeats := max(1, count)
        while repeats > 0 {
            before := app.active.cursor
            move(app, byte)
            if app.active.cursor == before {
                break
            }
            repeats = repeats - 1
        }
    } elif byte == KeyLowerG or byte == KeyLowerD or byte == KeyLowerY or byte == KeyLowerC or byte == KeyCtrlW {
        app.pending = byte
        app.operator_count = max(1, count)
    } elif byte == KeyLowerI or byte == KeyLowerA or byte == KeyLowerO or byte == KeyUpperI or byte == KeyUpperA or byte == KeyUpperO {
        return begin_insert(app, byte)
    } elif byte == KeyUpperC {
        return operator_motion(app, KeyLowerC, KeyDollar, max(1, count))
    } elif byte == KeyLowerS {
        return substitute_characters(app, max(1, count))
    } elif byte == KeyDot {
        return repeat_change(app, count)
    } elif byte == KeyLowerX {
        if at < line_end(&b.text, at) {
            begin_change(app, Change{command: byte, count: 1})
            app.group = app.group + 1
            yank(app, at, next_point(&b.text, at), false) @catch err {
                return err
            }
            return edit(app, at, next_point(&b.text, at), zero<u8[]>())
        }
    } elif byte == KeyLowerP {
        begin_change(app, Change{command: byte, count: 1})
        app.group = app.group + 1
        return paste_clipboard(app)
    } elif byte == KeyLowerU or byte == KeyCtrlR {
        return undo(app, byte == KeyCtrlR)
    } elif byte == KeyColon or byte == KeySlash {
        app.mode = Mode::Command
        if byte == KeySlash {
            app.mode = Mode::Search
            app.search_mode = Mode::Normal
        }
        lists::clear<u8>(&app.prompt)
    } elif byte == KeyLowerN or byte == KeyUpperN {
        find(app, byte == KeyUpperN)
    } elif byte == KeyCtrlP {
        return start_picker(app, PickerKind::Files)
    } elif byte == KeyCtrlB {
        return start_picker(app, PickerKind::Buffers)
    } elif byte == KeyCtrlF {
        return start_picker(app, PickerKind::ProjectSearch)
    } elif byte == KeyCtrlCaret {
        return switch_buffer(app, app.active.previous)
    }
    app.count = 0
    return nil
}
