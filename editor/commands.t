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
        lists::append<Position>(&p.positions, Position{buffer: p.buffer, cursor: p.cursor, top: p.top, left: p.left}) @catch err {
            return err
        }
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
    valid := (direction == 104 and px < cx) or (direction == 108 and px > cx) or (direction == 106 and py > cy) or (direction == 107 and py < cy)
    score := dx + dy * 4
    if direction == 104 or direction == 108 {
        score = dx * 4 + dy
    }
    if valid and score < *distance {
        *distance = score
        *best = p
    }
}

fn window_key(app *App, key u8) error {
    if key == 118 {
        return split_pane(app, true)
    }
    if key == 115 {
        return split_pane(app, false)
    }
    if key == 99 {
        close_pane(app, false)
        return nil
    }
    if key == 61 {
        equalize(app.root)
        return nil
    }
    if key == 104 or key == 106 or key == 107 or key == 108 {
        best := app.active
        distance u64 := 18446744073709551615
        focus_candidate(app.root, app.active, key, &best, &distance)
        app.active = best
        return nil
    }
    if key == 43 or key == 45 or key == 62 or key == 60 {
        p := app.active.parent
        vertical := key == 62 or key == 60
        while p != nil and p.vertical != vertical {
            p = p.parent
        }
        if p != nil {
            first := app.active
            while first.parent != p {
                first = first.parent
            }
            grow := key == 43 or key == 62
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
        if byte >= 65 and byte <= 90 {
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
    app.linewise = linewise
    app.message = "Yanked"
    return nil
}

fn paste_clipboard(app *App) error {
    b := buffer(app)
    at := app.active.cursor
    bytes := lists::view<u8>(&app.clipboard)
    if len(bytes) == 0 {
        return nil
    }
    if app.linewise {
        at = line_end(&b.text, at)
        if at < rope::size(b.text.root) {
            at = at + 1
            if bytes[len(bytes) - 1] != 10 {
                complete := lists::create<u8>()
                defer lists::free<u8>(&complete)
                lists::append_slice<u8>(&complete, bytes) @catch err {
                    return err
                }
                lists::append<u8>(&complete, 10) @catch err {
                    return err
                }
                return edit(app, at, at, lists::view<u8>(&complete))
            }
        } else {
            insert := lists::create<u8>()
            defer lists::free<u8>(&insert)
            lists::append<u8>(&insert, 10) @catch err {
                return err
            }
            lists::append_slice<u8>(&insert, bytes) @catch err {
                return err
            }
            if bytes[len(bytes) - 1] == 10 {
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
        return start_picker(app, 1)
    } elif name == "grep" {
        start_picker(app, 2) @catch err {
            return err
        }
        append_text(&app.picker.query, arg) @catch err {
            return err
        }
        return restart_picker(&app.picker)
    } elif name == "buffers" or name == "ls" {
        return start_picker(app, 3)
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
        app.message = "i/a/o insert | x dd yy p u Ctrl-r | :e/w/q/files/grep/buffers | Ctrl-w s/v/hjkl/c/=/< > + -"
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
    while b >= 128 and b < 192 and lists::count<u8>(bytes) > 0 {
        previous, exists := lists::pop<u8>(bytes)
        b = previous
    }
}

fn key(app *App, byte u8) error {
    if byte == 27 or byte == 3 {
        if app.picker.kind != 0 {
            close_picker(&app.picker)
        }
        app.mode = 0
        app.pending = 0
        app.group = app.group + 1
        return nil
    }
    if app.picker.kind != 0 {
        p := &app.picker
        if byte == 13 {
            return accept_picker(app)
        } elif byte == 10 or byte == 11 {
            count := lists::count<Match>(&p.matches)
            if byte == 10 and p.selected + 1 < count {
                p.selected = p.selected + 1
            }
            if byte == 11 and p.selected > 0 {
                p.selected = p.selected - 1
            }
        } elif byte == 8 and p.kind != 3 {
            p.hidden = p.hidden == false
            return restart_picker(p)
        } elif byte == 18 and p.kind == 2 {
            p.regex = p.regex == false
            return restart_picker(p)
        } elif byte == 9 and p.kind != 3 {
            p.ignored = p.ignored == false
            return restart_picker(p)
        } elif byte == 127 {
            pop_point(&p.query)
            return picker_changed(p)
        } elif byte >= 32 {
            lists::append<u8>(&p.query, byte) @catch err {
                return err
            }
            return picker_changed(p)
        }
        return nil
    }
    if app.mode == 2 or app.mode == 3 {
        if byte == 13 {
            mode := app.mode
            app.mode = 0
            if mode == 2 {
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
        } elif byte == 127 or byte == 8 {
            pop_point(&app.prompt)
        } elif byte >= 32 {
            lists::append<u8>(&app.prompt, byte) @catch err {
                return err
            }
        }
        return nil
    }
    b := buffer(app)
    at := app.active.cursor
    if app.mode == 1 {
        if byte == 127 or byte == 8 {
            if at > 0 {
                empty := zero<u8[]>()
                return edit(app, previous_point(&b.text, at), at, empty)
            }
        } elif byte == 13 or byte == 10 {
            return insert_newline(app, at)
        } elif byte == 9 or byte >= 32 {
            single u8[1] := .{byte}
            return edit(app, at, at, single[:])
        }
        return nil
    }
    app.message = ""
    if app.pending == 23 {
        app.pending = 0
        return window_key(app, byte)
    }
    if app.pending != 0 {
        previous := app.pending
        app.pending = 0
        if previous == 103 and byte == 103 {
            app.active.cursor = 0
        }
        if (previous == 100 and byte == 100) or (previous == 121 and byte == 121) {
            start := rope::line_start(&b.text, rope::line_at(&b.text, at))
            end := line_end(&b.text, at)
            if end < rope::size(b.text.root) {
                end = end + 1
            }
            yank(app, start, end, true) @catch err {
                return err
            }
            if previous == 100 {
                app.group = app.group + 1
                return edit(app, start, end, zero<u8[]>())
            }
        }
        return nil
    }
    if byte == 104 or byte == 106 or byte == 107 or byte == 108 or byte == 48 or byte == 36 or byte == 71 or byte == 119 {
        move(app, byte)
    } elif byte == 103 or byte == 100 or byte == 121 or byte == 23 {
        app.pending = byte
    } elif byte == 105 or byte == 97 or byte == 111 {
        app.mode = 1
        app.group = app.group + 1
        if byte == 97 and at < line_end(&b.text, at) {
            app.active.cursor = next_point(&b.text, at)
        }
        if byte == 111 {
            end2 := line_end(&b.text, at)
            insert_newline(app, end2) @catch err {
                return err
            }
        }
    } elif byte == 120 {
        if at < line_end(&b.text, at) {
            app.group = app.group + 1
            yank(app, at, next_point(&b.text, at), false) @catch err {
                return err
            }
            return edit(app, at, next_point(&b.text, at), zero<u8[]>())
        }
    } elif byte == 112 {
        app.group = app.group + 1
        return paste_clipboard(app)
    } elif byte == 117 or byte == 18 {
        return undo(app, byte == 18)
    } elif byte == 58 or byte == 47 {
        app.mode = 2
        if byte == 47 {
            app.mode = 3
        }
        lists::clear<u8>(&app.prompt)
    } elif byte == 110 or byte == 78 {
        find(app, byte == 78)
    } elif byte == 16 {
        return start_picker(app, 1)
    } elif byte == 2 {
        return start_picker(app, 3)
    } elif byte == 6 {
        return start_picker(app, 2)
    } elif byte == 30 {
        return switch_buffer(app, app.active.previous)
    }
    return nil
}
