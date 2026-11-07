package editor

use "pkg::rope"
use "std::lists"

fn indentation_end(r *rope::Rope, start u64, limit u64) u64 {
    end := start
    while end < limit and (rope::byte(r, end) == ByteSpace or rope::byte(r, end) == ByteTab) {
        end = end + 1
    }
    return end
}

fn begin_insert(app *App, command u8) error {
    begin_change(app, Change{command: command, count: 1})
    r := &buffer(app).text
    at := app.active.cursor
    app.mode = Mode::Insert
    app.group = app.group + 1
    if command == KeyUpperI {
        start := rope::line_start(r, rope::line_at(r, at))
        app.active.cursor = indentation_end(r, start, line_end(r, at))
    } elif command == KeyLowerA and at < line_end(r, at) {
        app.active.cursor = next_point(r, at)
    } elif command == KeyUpperA {
        app.active.cursor = line_end(r, at)
    } elif command == KeyLowerO {
        return insert_newline(app, line_end(r, at))
    } elif command == KeyUpperO {
        return insert_line_above(app)
    }
    return nil
}

fn substitute_characters(app *App, count u64) error {
    begin_change(app, Change{command: KeyLowerS, count: count})
    r := &buffer(app).text
    start := app.active.cursor
    end := start
    last := line_end(r, start)
    remaining := count
    while remaining > 0 and end < last {
        end = next_point(r, end)
        remaining = remaining - 1
    }
    return operate_range(app, KeyLowerC, start, end, false)
}

fn insert_line_above(app *App) error {
    r := &buffer(app).text
    start := rope::line_start(r, rope::line_at(r, app.active.cursor))
    end := indentation_end(r, start, line_end(r, start))
    data := rope::copy(r, start, end) @try
    defer lists::free<u8>(&data)
    lists::append<u8>(&data, ByteLF) @try
    edit(app, start, start, lists::view<u8>(&data)) @try
    app.active.cursor = end
    return nil
}
