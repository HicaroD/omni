package editor

use "pkg::rope"

fn operator_motion(app *App, operator u8, motion u8, count u64) error {
    if motion == KeySemicolon or motion == KeyComma {
        return repeat_character_find(app, motion == KeyComma, count, operator)
    }
    if character_find_motion(motion) {
        app.character_find = CharacterFind{motion: motion, operator: operator, count: count}
        return nil
    }
    if motion == KeyLowerW {
        return operator_word(app, operator, count)
    }
    r := &buffer(app).text
    at := app.active.cursor
    if motion == KeyLowerJ or motion == KeyLowerK {
        line := rope::line_at(r, at)
        if motion == KeyLowerK {
            target := line - min(line, count)
            app.active.cursor = rope::line_start(r, target)
            return operator_lines(app, operator, line - target + 1)
        }
        return operator_lines(app, operator, min(count, rope::breaks(r.root) - line) + 1)
    }
    if motion != KeyLowerH and motion != KeyLowerL and motion != KeyLowerB and motion != KeyZero and motion != KeyDollar {
        return nil
    }
    remaining := count
    if motion == KeyDollar {
        line := rope::line_at(r, at)
        target := line + min(count - 1, rope::breaks(r.root) - line)
        app.active.cursor = line_end(r, rope::line_start(r, target))
    } else {
        while remaining > 0 {
            before := app.active.cursor
            move(app, motion)
            if app.active.cursor == before {
                break
            }
            remaining = remaining - 1
        }
    }
    end := app.active.cursor
    app.active.cursor = at
    if at == end and (operator != KeyLowerC or motion != KeyDollar) {
        return nil
    }
    return operate_range(app, operator, min(at, end), max(at, end), false)
}

fn operator_word(app *App, operator u8, count u64) error {
    r := &buffer(app).text
    start := app.active.cursor
    end := start
    size := rope::size(r.root)
    change_word := operator == KeyLowerC and start < size and word_class(rope::byte(r, start)) != 0
    remaining := count
    while remaining > 0 and end < size {
        kind := word_class(rope::byte(r, end))
        if kind == 0 {
            end = next_point(r, end)
        } else {
            while end < size and word_class(rope::byte(r, end)) == kind {
                end = next_point(r, end)
            }
        }
        if change_word and remaining == 1 {
            break
        }
        while end < size and word_class(rope::byte(r, end)) == 0 {
            if remaining == 1 and kind != 0 and rope::byte(r, end) == ByteLF {
                break
            }
            if rope::byte(r, end) == ByteLF and end > 0 and rope::byte(r, end - 1) == ByteLF {
                break
            }
            end = next_point(r, end)
        }
        remaining = remaining - 1
    }
    if start == end {
        return nil
    }
    return operate_range(app, operator, start, end, false)
}

fn operator_lines(app *App, operator u8, count u64) error {
    r := &buffer(app).text
    first := rope::line_at(r, app.active.cursor)
    last := first + min(count - 1, rope::breaks(r.root) - first)
    start := rope::line_start(r, first)
    end := line_end(r, rope::line_start(r, last))
    if end < rope::size(r.root) {
        end = end + 1
    }
    return operate_range(app, operator, start, end, true)
}

fn operate_range(app *App, operator u8, start u64, end u64, linewise bool) error {
    if start != end or linewise {
        yank(app, start, end, linewise) @try
    }
    app.mode = Mode::Normal
    app.active.cursor = start
    if operator == KeyLowerY {
        return nil
    }
    app.group = app.group + 1
    r := &buffer(app).text
    if operator == KeyLowerC {
        app.mode = Mode::Insert
        if linewise and end > start and rope::byte(r, end - 1) == ByteLF {
            end = end - 1
        }
    } elif linewise and start > 0 and end == rope::size(r.root) {
        if start == end or rope::byte(r, end - 1) != ByteLF {
            start = start - 1
        }
    }
    return edit(app, start, end, zero<u8[]>())
}
