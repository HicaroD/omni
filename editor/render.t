package editor

use "std::lists"
use "std::strings"
use "std::terminal"
use "std::memory"
use "pkg::rope"
use "vendor::platform"

fn csi(out *lists::List<u8>, suffix string) error {
    lists::append<u8>(out, 27) @catch err {
        return err
    }
    lists::append<u8>(out, 91) @catch err {
        return err
    }
    return append_text(out, suffix)
}

fn position(out *lists::List<u8>, x u64, y u64) error {
    csi(out, "") @catch err {
        return err
    }
    number(out, y + 1) @catch err {
        return err
    }
    append_text(out, ";") @catch err {
        return err
    }
    number(out, x + 1) @catch err {
        return err
    }
    return append_text(out, "H")
}

fn point(r *rope::Rope, at u64) (u32, u64) {
    a := platform::widen(rope::byte(r, at))
    if a < 128 {
        return a, 1
    }
    length u64 := 0
    cp u32 := 0
    if a >= 194 and a <= 223 {
        length = 2
        cp = a - 192
    }
    if a >= 224 and a <= 239 {
        length = 3
        cp = a - 224
    }
    if a >= 240 and a <= 244 {
        length = 4
        cp = a - 240
    }
    if length == 0 or at + length > rope::size(r.root) {
        return 63, 1
    }
    i u64 := 1
    while i < length {
        b := platform::widen(rope::byte(r, at + i))
        if b < 128 or b > 191 {
            return 63, 1
        }
        cp = cp * 64 + b - 128
        i = i + 1
    }
    if (length == 3 and cp < 2048) or (length == 4 and cp < 65536) or cp > 1114111 or (cp >= 55296 and cp <= 57343) {
        return 63, 1
    }
    return cp, length
}

fn cell_width(cp u32, column u64) u64 {
    if cp == 9 {
        return 4 - (column - (column / 4) * 4)
    }
    w := platform::width(cp)
    if w == 0 {
        return 0
    }
    if w == 2 {
        return 2
    }
    return 1
}

fn display_column(r *rope::Rope, start u64, end u64) u64 {
    column u64 := 0
    at := start
    while at < end {
        cp, count := point(r, at)
        column = column + cell_width(cp, column)
        at = at + count
    }
    return column
}

fn spaces(out *lists::List<u8>, count u64) error {
    i u64 := 0
    while i < count {
        lists::append<u8>(out, 32) @catch err {
            return err
        }
        i = i + 1
    }
    return nil
}

fn draw_line(out *lists::List<u8>, r *rope::Rope, start u64, left u64, width u64) error {
    at := start
    column u64 := 0
    drawn u64 := 0
    while at < rope::size(r.root) and rope::byte(r, at) != 10 and column < left + width {
        cp, count := point(r, at)
        cells := cell_width(cp, column)
        if column >= left and column + cells <= left + width {
            if cp == 9 {
                spaces(out, cells) @catch err {
                    return err
                }
            } else {
                if cp < 32 or cp == 127 or platform::width(cp) < 0 or (cp == 63 and rope::byte(r, at) != 63) {
                    lists::append<u8>(out, 63) @catch err {
                        return err
                    }
                } else {
                    if cells > 0 or drawn > 0 {
                        i u64 := 0
                        while i < count {
                            lists::append<u8>(out, rope::byte(r, at + i)) @catch err {
                                return err
                            }
                            i = i + 1
                        }
                    }
                }
            }
            drawn = drawn + cells
        } else {
            if column < left and column + cells > left {
                gap := min(column + cells - left, width)
                spaces(out, gap) @catch err {
                    return err
                }
                drawn = drawn + gap
            }
        }
        column = column + cells
        at = at + count
    }
    if drawn < width {
        return spaces(out, width - drawn)
    }
    return nil
}

fn label(out *lists::List<u8>, text string, width u64) error {
    bytes := text_bytes(text) @catch err {
        return err
    }
    defer lists::free<u8>(&bytes)
    temp := zero<rope::Rope>()
    defer rope::free(&temp)
    rope::replace(&temp, 0, 0, lists::view<u8>(&bytes)) @catch err {
        return err
    }
    return draw_line(out, &temp, 0, 0, width)
}

fn layout(p *Pane, x u64, y u64, width u64, height u64) {
    p.x = x
    p.y = y
    p.width = width
    p.height = height
    if p.first == nil {
        return
    }
    if p.vertical {
        usable := width
        if usable > 0 {
            usable = usable - 1
        }
        first := usable * p.ratio / 100
        layout(p.first, x, y, first, height)
        layout(p.second, x + first + 1, y, usable - first, height)
    } else {
        first_height := height * p.ratio / 100
        layout(p.first, x, y, width, first_height)
        layout(p.second, x, y + first_height, width, height - first_height)
    }
}

fn draw_pane(app *App, p *Pane) error {
    if p.width == 0 or p.height == 0 {
        return nil
    }
    if p.first != nil {
        draw_pane(app, p.first) @catch err {
            return err
        }
        draw_pane(app, p.second) @catch err {
            return err
        }
        if p.vertical {
            i u64 := 0
            while i < p.height {
                position(&app.frame, p.second.x - 1, p.y + i) @catch err {
                    return err
                }
                append_text(&app.frame, "|") @catch err {
                    return err
                }
                i = i + 1
            }
        }
        return nil
    }
    items := lists::view<*Buffer>(&app.buffers)
    b := items[p.buffer]
    p.cursor = min(p.cursor, rope::size(b.text.root))
    line := rope::line_at(&b.text, p.cursor)
    rows := p.height - 1
    if line < p.top {
        p.top = line
    }
    if rows > 0 and line >= p.top + rows {
        p.top = line - rows + 1
    }
    column := display_column(&b.text, rope::line_start(&b.text, line), p.cursor)
    if column < p.left {
        p.left = column
    }
    if column >= p.left + p.width {
        p.left = column - p.width + 1
    }
    row u64 := 0
    while row < rows {
        position(&app.frame, p.x, p.y + row) @catch err {
            return err
        }
        if p.top + row <= rope::breaks(b.text.root) {
            start := rope::line_start(&b.text, p.top + row)
            draw_line(&app.frame, &b.text, start, p.left, p.width) @catch err {
                return err
            }
        } else {
            label(&app.frame, "~", p.width) @catch err {
                return err
            }
        }
        row = row + 1
    }
    position(&app.frame, p.x, p.y + rows) @catch err {
        return err
    }
    csi(&app.frame, "7m") @catch err {
        return err
    }
    status := lists::create<u8>()
    defer lists::free<u8>(&status)
    if p == app.active {
        append_text(&status, " > ") @catch err {
            return err
        }
    } else {
        append_text(&status, "   ") @catch err {
            return err
        }
    }
    name := strings::view(&b.path)
    if name == "" {
        name = "[No Name]"
    }
    parts := strings::split(name, "/") @catch err {
        return err
    }
    defer lists::free<string>(&parts)
    names := lists::view<string>(&parts)
    if len(names) > 0 {
        name = names[len(names) - 1]
    }
    append_text(&status, name) @catch err {
        return err
    }
    if b.revision != b.saved {
        append_text(&status, " [+]") @catch err {
            return err
        }
    }
    append_text(&status, "  ") @catch err {
        return err
    }
    number(&status, line + 1) @catch err {
        return err
    }
    append_text(&status, ":") @catch err {
        return err
    }
    number(&status, column + 1) @catch err {
        return err
    }
    status_text := owned_bytes(lists::view<u8>(&status)) @catch err {
        return err
    }
    defer strings::free(&status_text)
    label(&app.frame, strings::view(&status_text), p.width) @catch err {
        return err
    }
    return csi(&app.frame, "0m")
}

fn preview(app *App) error {
    p := &app.picker
    matches := lists::view<Match>(&p.matches)
    if len(matches) == 0 {
        return nil
    }
    selected := &matches[p.selected]
    key := selected.index
    if p.preview_ready and p.preview_key == key {
        return nil
    }
    rope::free(&p.preview)
    p.preview_ready = true
    p.preview_key = key
    items := lists::view<Item>(&p.items)
    item := &items[key]
    if p.kind == 3 {
        return nil
    }
    c := strings::to_c(strings::view(&item.path)) @catch err {
        return err
    }
    defer strings::free_c(&c)
    data rawptr := nil
    count u64 := 0
    result := platform::preview(strings::c_view(&c), &data, &count)
    defer memory::free(data)
    if result != 0 {
        return nil
    }
    return rope::replace(&p.preview, 0, 0, slice_from_raw<u8>(data, min(count, 1048576)))
}

fn draw_picker(app *App, width u64, height u64) error {
    p := &app.picker
    preview(app) @catch err {
        return err
    }
    x u64 := 2
    y u64 := 1
    w := width - 4
    h := height - 3
    position(&app.frame, x, y) @catch err {
        return err
    }
    csi(&app.frame, "7m") @catch err {
        return err
    }
    title := " FILES  Ctrl-h hidden | Tab ignored | Ctrl-j/k select | Enter open"
    if p.kind == 2 {
        title = " SEARCH  Ctrl-r regex | Ctrl-h hidden | Ctrl-j/k select | Enter open"
    }
    if p.kind == 3 {
        title = " BUFFERS  Ctrl-j/k select | Enter open | Esc close"
    }
    label(&app.frame, title, w) @catch err {
        return err
    }
    csi(&app.frame, "0m") @catch err {
        return err
    }
    position(&app.frame, x, y + 1) @catch err {
        return err
    }
    query := lists::create<u8>()
    defer lists::free<u8>(&query)
    append_text(&query, "> ") @catch err {
        return err
    }
    lists::append_slice<u8>(&query, lists::view<u8>(&p.query)) @catch err {
        return err
    }
    query_text := owned_bytes(lists::view<u8>(&query)) @catch err {
        return err
    }
    defer strings::free(&query_text)
    label(&app.frame, strings::view(&query_text), w) @catch err {
        return err
    }
    matches := lists::view<Match>(&p.matches)
    items := lists::view<Item>(&p.items)
    rows := h - 3
    top u64 := 0
    if p.selected >= rows {
        top = p.selected - rows + 1
    }
    list_width := w / 2
    row u64 := 0
    while row < rows {
        position(&app.frame, x, y + row + 2) @catch err {
            return err
        }
        index := top + row
        if index < len(matches) {
            if index == p.selected {
                csi(&app.frame, "7m") @catch err {
                    return err
                }
            }
            match_item := &matches[index]
            result_item := &items[match_item.index]
            label(&app.frame, strings::view(&result_item.label), list_width) @catch err {
                return err
            }
            csi(&app.frame, "0m") @catch err {
                return err
            }
        } else {
            spaces(&app.frame, list_width) @catch err {
                return err
            }
        }
        append_text(&app.frame, "|") @catch err {
            return err
        }
        r := &p.preview
        preview_top u64 := 0
        if len(matches) > 0 {
            selected_result := &matches[p.selected]
            item := &items[selected_result.index]
            if item.line > 3 {
                preview_top = item.line - 3
            }
            if p.kind == 3 {
                buffers := lists::view<*Buffer>(&app.buffers)
                selected_buffer := buffers[item.buffer]
                r = &selected_buffer.text
            }
        }
        draw_line(&app.frame, r, rope::line_start(r, preview_top + row), 0, w - list_width - 1) @catch err {
            return err
        }
        row = row + 1
    }
    position(&app.frame, x, y + h - 1) @catch err {
        return err
    }
    footer := "Literal / smart case"
    if p.regex {
        footer = "Regex / smart case"
    }
    if p.hidden {
        footer = "Hidden files included"
    }
    if p.ignored {
        footer = "Ignored files included (Tab toggles)"
    }
    if p.process != nil {
        footer = "Searching..."
    }
    if p.limited {
        footer = "Result limit reached (50,000 candidates; top 100 shown)"
    }
    if p.failed {
        footer = "rg failed: check installation, query, or permissions"
    }
    return label(&app.frame, footer, w)
}

fn draw(app *App, output *terminal::Handle) error {
    size := terminal::size(output) @catch err {
        return err
    }
    width := min(size.columns, 65535)
    height := min(size.rows, 65535)
    if width < 8 or height < 4 {
        return nil
    }
    lists::clear<u8>(&app.frame)
    csi(&app.frame, "?25l") @catch err {
        return err
    }
    csi(&app.frame, "2J") @catch err {
        return err
    }
    layout(app.root, 0, 0, width, height - 1)
    draw_pane(app, app.root) @catch err {
        return err
    }
    position(&app.frame, 0, height - 1) @catch err {
        return err
    }
    if app.mode == 2 or app.mode == 3 {
        prefix := ":"
        if app.mode == 3 {
            prefix = "/"
        }
        append_text(&app.frame, prefix) @catch err {
            return err
        }
        prompt := owned_bytes(lists::view<u8>(&app.prompt)) @catch err {
            return err
        }
        defer strings::free(&prompt)
        label(&app.frame, strings::view(&prompt), width - 1) @catch err {
            return err
        }
    } else {
        text := app.message
        if text == "" {
            text = "NORMAL  :files  :grep  :buffers  :help"
            if app.mode == 1 {
                text = "INSERT"
            }
        }
        label(&app.frame, text, width) @catch err {
            return err
        }
    }
    if app.picker.kind != 0 and width >= 30 and height >= 10 {
        draw_picker(app, width, height) @catch err {
            return err
        }
    } else {
        p := app.active
        if app.mode == 2 or app.mode == 3 {
            position(&app.frame, min(1 + lists::count<u8>(&app.prompt), width - 1), height - 1) @catch err {
                return err
            }
        } else {
            b := buffer(app)
            line := rope::line_at(&b.text, p.cursor)
            col := display_column(&b.text, rope::line_start(&b.text, line), p.cursor)
            if p.width > 0 and p.height > 1 {
                position(&app.frame, p.x + min(col - p.left, p.width - 1), p.y + min(line - p.top, p.height - 2)) @catch err {
                    return err
                }
            }
        }
        csi(&app.frame, "?25h") @catch err {
            return err
        }
    }
    return terminal::write_all(output, lists::view<u8>(&app.frame))
}
