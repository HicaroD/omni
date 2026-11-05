package editor

use "pkg::rope"
use "std::lists"

fn visual(app *App) bool {
    return app.mode == Mode::VisualCharacter or app.mode == Mode::VisualLine or app.mode == Mode::VisualBlock
}

struct Selection {
    mode Mode
    start u64
    end u64
    bounds Block
}

// Compute ranges once per frame, not once per highlighted terminal cell.
fn render_selection(app *App) Selection {
    s := Selection{mode: app.mode}
    if visual(app) {
        start, end := visual_range(app)
        s.start = start
        s.end = end
        if app.mode == Mode::VisualBlock {
            s.bounds = visual_block(app)
        } else {
            r := &buffer(app).text
            s.bounds.first = rope::line_at(r, min(app.active.cursor, app.visual_anchor))
            s.bounds.last = rope::line_at(r, max(app.active.cursor, app.visual_anchor))
        }
    }
    return s
}

fn visual_selected(s *Selection, line u64, at u64, column u64, width u64, eol bool) bool {
    if s.mode == Mode::VisualBlock {
        return eol == false and line >= s.bounds.first and line <= s.bounds.last and column < s.bounds.right and column + width > s.bounds.left
    }
    if s.mode == Mode::VisualLine {
        return line >= s.bounds.first and line <= s.bounds.last
    }
    return at >= s.start and (at < s.end or (eol and s.start == s.end and at == s.start))
}

fn visual_range(app *App) (u64, u64) {
    r := &buffer(app).text
    start := min(app.active.cursor, app.visual_anchor)
    last := max(app.active.cursor, app.visual_anchor)
    end := next_point(r, last)
    if app.mode == Mode::VisualLine {
        start = rope::line_start(r, rope::line_at(r, start))
        end = line_end(r, last)
        if end < rope::size(r.root) {
            end = end + 1
        }
    }
    return start, end
}

fn visual_key(app *App, byte u8) error {
    if app.pending == 0 and character_find_motion(byte) {
        app.character_find = CharacterFind{motion: byte, count: 1}
        return nil
    }
    if app.pending == 0 and (byte == KeySemicolon or byte == KeyComma) {
        return repeat_character_find(app, byte == KeyComma, 1, 0)
    }
    if byte == KeySlash {
        app.search_mode = app.mode
        app.mode = Mode::Search
        app.pending = 0
        lists::clear<u8>(&app.prompt)
        return nil
    }
    if byte == KeyLowerN or byte == KeyUpperN {
        find(app, byte == KeyUpperN)
        app.visual_column = cursor_column(&buffer(app).text, app.active.cursor)
        app.visual_wanted = app.visual_column
        return nil
    }
    if app.mode == Mode::VisualBlock and (byte == KeyUpperI or byte == KeyUpperA) {
        bounds := visual_block(app)
        column := bounds.left
        if byte == KeyUpperA {
            column = bounds.right
        }
        app.group = app.group + 1
        app.mode = Mode::Insert
        app.block_insert = true
        app.block_insert_column = column
        app.block_insert_eol = byte == KeyUpperA and app.visual_eol
        lists::clear<u64>(&app.block_insert_rows)
        r := &buffer(app).text
        line := bounds.first + 1
        while line <= bounds.last {
            at := rope::line_start(r, line)
            if byte == KeyUpperA or cursor_column(r, line_end(r, at)) >= column {
                lists::append<u64>(&app.block_insert_rows, line) @try
            }
            line = line + 1
        }
        if app.block_insert_eol {
            column = cursor_column(r, line_end(r, rope::line_start(r, bounds.first)))
        }
        block_insert_row(app, bounds.first, column, zero<u8[]>()) @try
        app.active.cursor = column_offset(r, bounds.first, column)
        app.block_insert_start = app.active.cursor
        return nil
    }
    if app.mode == Mode::VisualBlock and (byte == KeyLowerD or byte == KeyLowerX or byte == KeyLowerY or byte == KeyLowerC) {
        return block_operator(app, byte)
    }
    if byte == KeyLowerP or byte == KeyUpperP {
        if lists::count<u8>(&app.clipboard) == 0 and app.register_kind == RegisterKind::Characterwise {
            app.message = "Yank register is empty"
            return nil
        }
        data := lists::create<u8>()
        defer lists::free<u8>(&data)
        lists::append_slice<u8>(&data, lists::view<u8>(&app.clipboard)) @try
        if app.mode == Mode::VisualBlock {
            bounds := visual_block(app)
            kind := app.register_kind
            width := app.block_width
            if byte == KeyLowerP {
                block_yank(app, bounds) @try
            }
            app.group = app.group + 1
            app.mode = Mode::Normal
            line := bounds.last + 1
            while line > bounds.first {
                line = line - 1
                block_delete_row(app, line, bounds.left, bounds.right) @try
                if kind == RegisterKind::Characterwise {
                    block_insert_row(app, line, bounds.left, lists::view<u8>(&data)) @try
                }
            }
            if kind == RegisterKind::Linewise {
                app.active.cursor = rope::line_start(&buffer(app).text, bounds.last)
                return paste_register(app, lists::view<u8>(&data), kind, width)
            }
            if kind == RegisterKind::Blockwise {
                put_block(app, lists::view<u8>(&data), bounds.first, bounds.left, width) @try
            }
            app.active.cursor = column_offset(&buffer(app).text, bounds.first, bounds.left)
            return nil
        }
        start, end := visual_range(app)
        r := &buffer(app).text
        kind := app.register_kind
        if kind == RegisterKind::Blockwise and app.mode == Mode::VisualCharacter {
            first := rope::line_at(r, start)
            column := cursor_column(r, start)
            width := app.block_width
            if byte == KeyLowerP {
                yank(app, start, end, false) @try
            }
            app.group = app.group + 1
            app.mode = Mode::Normal
            edit(app, start, end, zero<u8[]>()) @try
            return put_block(app, lists::view<u8>(&data), first, column, width)
        }
        if app.mode == Mode::VisualLine {
            bytes := lists::view<u8>(&data)
            terminated := end > start and rope::byte(r, end - 1) == ByteLF
            if terminated and (len(bytes) == 0 or bytes[len(bytes) - 1] != ByteLF) {
                lists::append<u8>(&data, ByteLF) @try
            }
            if terminated == false and len(bytes) > 0 and bytes[len(bytes) - 1] == ByteLF {
                lists::pop<u8>(&data)
            }
        } elif kind == RegisterKind::Linewise {
            wrapped := lists::create<u8>()
            defer lists::free<u8>(&wrapped)
            lists::append<u8>(&wrapped, ByteLF) @try
            lists::append_slice<u8>(&wrapped, lists::view<u8>(&data)) @try
            bytes := lists::view<u8>(&wrapped)
            if bytes[len(bytes) - 1] != ByteLF {
                lists::append<u8>(&wrapped, ByteLF) @try
            }
            lists::free<u8>(&data)
            data = wrapped
            wrapped = lists::create<u8>()
        }
        if byte == KeyLowerP {
            yank(app, start, end, app.mode == Mode::VisualLine) @try
        }
        app.group = app.group + 1
        app.mode = Mode::Normal
        return edit(app, start, end, lists::view<u8>(&data))
    }
    if byte == KeyLowerO or byte == KeyUpperO {
        if app.mode == Mode::VisualBlock {
            column := app.visual_column
            app.visual_column = app.visual_anchor_column
            app.visual_anchor_column = column
            app.visual_wanted = app.visual_column
            if byte == KeyUpperO {
                r := &buffer(app).text
                app.active.cursor = column_offset(r, rope::line_at(r, app.active.cursor), app.visual_column)
                app.visual_anchor = column_offset(r, rope::line_at(r, app.visual_anchor), app.visual_anchor_column)
                return nil
            }
        }
        at := app.active.cursor
        app.active.cursor = app.visual_anchor
        app.visual_anchor = at
        return nil
    }
    if byte == KeyLowerD or byte == KeyLowerY or byte == KeyLowerX or byte == KeyLowerC {
        start, end := visual_range(app)
        linewise := app.mode == Mode::VisualLine
        return operate_range(app, byte, start, end, linewise)
    }
    if app.pending == KeyLowerG {
        app.pending = 0
        if byte == KeyLowerG {
            app.active.cursor = 0
            app.visual_column = 0
            app.visual_wanted = 0
            app.visual_eol = false
        }
        return nil
    }
    if byte == KeyLowerG {
        app.pending = byte
    } else {
        wanted := app.visual_wanted
        move(app, byte)
        if app.mode == Mode::VisualBlock {
            r := &buffer(app).text
            if byte == KeyDollar {
                app.visual_eol = true
            } elif byte != KeyLowerJ and byte != KeyLowerK {
                app.visual_eol = false
            }
            if byte == KeyLowerJ or byte == KeyLowerK {
                if app.visual_eol {
                    app.active.cursor = line_end(r, app.active.cursor)
                } else {
                    app.active.cursor = column_offset(r, rope::line_at(r, app.active.cursor), wanted)
                }
                app.visual_column = cursor_column(r, app.active.cursor)
            } else {
                app.visual_column = cursor_column(r, app.active.cursor)
                app.visual_wanted = app.visual_column
            }
        }
    }
    return nil
}

fn cursor_column(r *rope::Rope, at u64) u64 {
    return display_column(r, rope::line_start(r, rope::line_at(r, at)), at)
}

struct Block {
    first u64
    last u64
    left u64
    right u64
}

fn visual_block(app *App) Block {
    r := &buffer(app).text
    a := rope::line_at(r, app.visual_anchor)
    b := rope::line_at(r, app.active.cursor)
    right := max(block_endpoint_right(r, app.active.cursor, app.visual_column), block_endpoint_right(r, app.visual_anchor, app.visual_anchor_column))
    bounds := Block{first: min(a, b), last: max(a, b), left: min(app.visual_column, app.visual_anchor_column), right: right}
    if app.visual_eol {
        bounds.left = app.visual_anchor_column
        bounds.right = bounds.left
        line := bounds.first
        while line <= bounds.last {
            end := line_end(r, rope::line_start(r, line))
            bounds.right = max(bounds.right, cursor_column(r, end))
            line = line + 1
        }
    }
    return bounds
}

fn block_endpoint_right(r *rope::Rope, at u64, column u64) u64 {
    if at < line_end(r, at) {
        cp, count := point(r, at)
        return column + max(1, cell_width(cp, column))
    }
    return column + 1
}

fn column_offset(r *rope::Rope, line u64, column u64) u64 {
    at := rope::line_start(r, line)
    end := line_end(r, at)
    col u64 := 0
    while at < end {
        cp, count := point(r, at)
        width := cell_width(cp, col)
        if col + width > column {
            break
        }
        col = col + width
        at = at + count
    }
    return at
}

fn block_operator(app *App, byte u8) error {
    r := &buffer(app).text
    bounds := visual_block(app)
    block_yank(app, bounds) @try
    app.mode = Mode::Normal
    line := bounds.last + 1
    if byte != KeyLowerY {
        app.group = app.group + 1
        while line > bounds.first {
            line = line - 1
            block_delete_row(app, line, bounds.left, bounds.right) @try
        }
    }
    app.active.cursor = column_offset(r, bounds.first, bounds.left)
    if byte == KeyLowerC {
        app.mode = Mode::Insert
        app.block_insert = true
        app.block_insert_start = app.active.cursor
        app.block_insert_column = bounds.left
        app.block_insert_eol = false
        lists::clear<u64>(&app.block_insert_rows)
        line = bounds.first + 1
        while line <= bounds.last {
            if cursor_column(r, line_end(r, rope::line_start(r, line))) >= bounds.left {
                lists::append<u64>(&app.block_insert_rows, line) @try
            }
            line = line + 1
        }
    }
    return nil
}

fn block_yank(app *App, bounds Block) error {
    r := &buffer(app).text
    data := lists::create<u8>()
    defer lists::free<u8>(&data)
    line := bounds.first
    while line <= bounds.last {
        block_copy_row(r, line, bounds.left, bounds.right, &data) @try
        if line < bounds.last {
            lists::append<u8>(&data, ByteLF) @try
        }
        line = line + 1
    }
    lists::free<u8>(&app.clipboard)
    app.clipboard = data
    data = lists::create<u8>()
    app.register_kind = RegisterKind::Blockwise
    app.block_width = bounds.right - bounds.left
    return nil
}

fn cancel_block_insert(app *App) {
    app.block_insert = false
    lists::clear<u64>(&app.block_insert_rows)
}

fn finish_block_insert(app *App) error {
    app.block_insert = false
    defer lists::clear<u64>(&app.block_insert_rows)
    r := &buffer(app).text
    start := app.block_insert_start
    end := app.active.cursor
    if end <= start or rope::line_at(r, start) != rope::line_at(r, end) {
        return nil
    }
    bytes := rope::copy(r, start, end) @try
    defer lists::free<u8>(&bytes)
    for line in lists::view<u64>(&app.block_insert_rows) {
        column := app.block_insert_column
        if app.block_insert_eol {
            column = cursor_column(r, line_end(r, rope::line_start(r, line)))
        }
        block_insert_row(app, line, column, lists::view<u8>(&bytes)) @try
    }
    app.active.cursor = start
    return nil
}

fn block_copy_row(r *rope::Rope, line u64, left u64, right u64, out *lists::List<u8>) error {
    at := rope::line_start(r, line)
    end := line_end(r, at)
    col u64 := 0
    included := false
    while at < end {
        cp, count := point(r, at)
        width := cell_width(cp, col)
        if width > 0 {
            if col >= right {
                break
            }
            included = col + width > left
        }
        if included {
            if cp == CodePointTab {
                spaces(out, min(col + width, right) - max(col, left)) @try
            } else {
                part := rope::copy(r, at, at + count) @try
                defer lists::free<u8>(&part)
                lists::append_slice<u8>(out, lists::view<u8>(&part)) @try
            }
        }
        col = col + width
        at = at + count
    }
    return nil
}

fn block_delete_row(app *App, line u64, left u64, right u64) error {
    r := &buffer(app).text
    start := column_offset(r, line, left)
    end := column_offset(r, line, right)
    padding u64 := 0
    if start < line_end(r, start) and rope::byte(r, start) == ByteTab {
        padding = left - cursor_column(r, start)
    }
    if end < line_end(r, end) and cursor_column(r, end) < right {
        cp, count := point(r, end)
        if cp == CodePointTab {
            col := cursor_column(r, end)
            padding = padding + col + cell_width(cp, col) - right
        }
        end = end + count
    }
    data := lists::create<u8>()
    defer lists::free<u8>(&data)
    spaces(&data, padding) @try
    return edit(app, start, end, lists::view<u8>(&data))
}

fn block_insert_row(app *App, line u64, column u64, bytes u8[]) error {
    r := &buffer(app).text
    while line > rope::breaks(r.root) {
        newline u8[1] := .{ByteLF}
        edit(app, rope::size(r.root), rope::size(r.root), newline[:]) @try
    }
    at := column_offset(r, line, column)
    col := cursor_column(r, at)
    end := at
    data := lists::create<u8>()
    defer lists::free<u8>(&data)
    spaces(&data, column - col) @try
    lists::append_slice<u8>(&data, bytes) @try
    if at < line_end(r, at) and rope::byte(r, at) == ByteTab and column > col {
        end = at + 1
        spaces(&data, col + cell_width(CodePointTab, col) - column) @try
    }
    return edit(app, at, end, lists::view<u8>(&data))
}

fn put_block(app *App, bytes u8[], first u64, column u64, width u64) error {
    start u64 := 0
    at u64 := 0
    line := first
    while at <= len(bytes) {
        if at == len(bytes) or bytes[at] == ByteLF {
            row := bytes[start:at] @try
            padded := lists::create<u8>()
            defer lists::free<u8>(&padded)
            lists::append_slice<u8>(&padded, row) @try
            r := &buffer(app).text
            if line <= rope::breaks(r.root) and column < cursor_column(r, line_end(r, rope::line_start(r, line))) {
                temp := zero<rope::Rope>()
                defer rope::free(&temp)
                rope::replace(&temp, 0, 0, row) @try
                used := display_column(&temp, 0, len(row))
                if used < width {
                    spaces(&padded, width - used) @try
                }
            }
            block_insert_row(app, line, column, lists::view<u8>(&padded)) @try
            line = line + 1
            start = at + 1
        }
        at = at + 1
    }
    app.active.cursor = column_offset(&buffer(app).text, first, column)
    return nil
}
