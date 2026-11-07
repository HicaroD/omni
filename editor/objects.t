package editor

use "pkg::rope"

fn operator_word_object(app *App, operator u8, around bool, count u64) error {
    if operator == KeyLowerD or operator == KeyLowerC {
        begin_change(app, Change{command: operator, object: true, around: around, count: count})
    }
    r := &buffer(app).text
    start := app.active.cursor
    end := start
    size := rope::size(r.root)
    if start >= size {
        return nil
    }
    kind := word_class(rope::byte(r, start))
    while start > 0 {
        previous := previous_point(r, start)
        if word_class(rope::byte(r, previous)) != kind {
            break
        }
        start = previous
    }
    while end < size and word_class(rope::byte(r, end)) == kind {
        end = next_point(r, end)
    }
    if around and kind == 0 and end < size {
        next_kind := word_class(rope::byte(r, end))
        while end < size and word_class(rope::byte(r, end)) == next_kind {
            end = next_point(r, end)
        }
    }
    remaining := count - 1
    while remaining > 0 and end < size {
        if around {
            while end < size and word_class(rope::byte(r, end)) == 0 {
                end = next_point(r, end)
            }
        }
        if end == size {
            break
        }
        next_kind := word_class(rope::byte(r, end))
        while end < size and word_class(rope::byte(r, end)) == next_kind {
            end = next_point(r, end)
        }
        remaining = remaining - 1
    }
    if around and kind != 0 {
        trailing := end
        while end < size and (rope::byte(r, end) == ByteSpace or rope::byte(r, end) == ByteTab) {
            end = end + 1
        }
        if trailing == end {
            while start > 0 and (rope::byte(r, start - 1) == ByteSpace or rope::byte(r, start - 1) == ByteTab) {
                start = start - 1
            }
        }
    }
    return operate_range(app, operator, start, end, false)
}
