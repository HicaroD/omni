package editor

use "std::lists"
use "std::memory"
use "pkg::rope"

enum ChangeInputKind {
    Key
    Arrow
    Literal
}

struct ChangeInput {
    kind ChangeInputKind
    byte u8
}

struct Change {
    command u8
    motion u8
    object bool
    around bool
    find CharacterFind
    find_repeated bool
    count u64
    visual_mode Mode
    lines u64
    points u64
    columns u64
    eol bool
    input lists::List<ChangeInput>
}

fn record_change_input(app *App, kind ChangeInputKind, byte u8) error {
    if app.change_active and app.mode == Mode::Insert and app.picker.kind == PickerKind::None and app.repeating == false {
        lists::append<ChangeInput>(&app.change.input, ChangeInput{kind: kind, byte: byte}) @try
    }
    return nil
}

fn begin_change(app *App, change Change) {
    if app.repeating or app.change_active {
        return
    }
    app.change = change
    app.change_active = true
    app.change_edited = false
}

fn begin_visual_change(app *App, command u8) {
    if app.repeating {
        return
    }
    if app.mode == Mode::VisualBlock {
        bounds := visual_block(app)
        begin_change(app, Change{command: command, count: 1, visual_mode: app.mode, lines: bounds.last - bounds.first + 1, columns: bounds.right - bounds.left, eol: app.visual_eol})
        return
    }
    if app.mode == Mode::VisualLine {
        r := &buffer(app).text
        first := rope::line_at(r, min(app.active.cursor, app.visual_anchor))
        last := rope::line_at(r, max(app.active.cursor, app.visual_anchor))
        begin_change(app, Change{command: command, count: 1, visual_mode: app.mode, lines: last - first + 1})
        return
    }
    start, end := visual_range(app)
    count u64 := 0
    r := &buffer(app).text
    lines := rope::line_at(r, end) - rope::line_at(r, start)
    if lines > 0 {
        start = rope::line_start(r, rope::line_at(r, end))
    }
    while start < end {
        start = next_point(r, start)
        count = count + 1
    }
    begin_change(app, Change{command: command, count: 1, visual_mode: app.mode, lines: lines, points: count})
}

fn finish_change(app *App) {
    if app.change_edited {
        lists::free<ChangeInput>(&app.last_change.input)
        app.last_change = memory::take<Change>(&app.change)
    } else {
        lists::free<ChangeInput>(&app.change.input)
    }
    app.change_active = false
    app.change_edited = false
}

fn discard_change(app *App) {
    lists::free<ChangeInput>(&app.change.input)
    app.change_active = false
    app.change_edited = false
}

fn repeat_change(app *App, count u64) error {
    change := app.last_change
    if change.command == 0 or app.repeating {
        return nil
    }
    if count > 0 {
        change.count = count
        change.find.count = count
        app.last_change.count = count
        app.last_change.find.count = count
    }
    app.repeating = true
    defer app.repeating = false
    app.group = app.group + 1
    app.repeat_group = app.group
    remaining u64 := 1
    if change.visual_mode != Mode::Normal or (change.command != KeyLowerD and change.command != KeyLowerC and change.command != KeyLowerS) {
        remaining = change.count
    }
    while remaining > 0 {
        before := buffer(app).serial
        replay_change(app, &change) @try
        if app.mode == Mode::Insert {
            replay_change_input(app) @try
        }
        if buffer(app).serial == before {
            break
        }
        remaining = remaining - 1
    }
    return nil
}

fn replay_change_input(app *App) error {
    inputs := lists::view<ChangeInput>(&app.last_change.input)
    literal := lists::create<u8>()
    defer lists::free<u8>(&literal)
    i u64 := 0
    while i < len(inputs) {
        input := inputs[i]
        if input.kind == ChangeInputKind::Literal {
            lists::clear<u8>(&literal)
            while i < len(inputs) and inputs[i].kind == ChangeInputKind::Literal {
                lists::append<u8>(&literal, inputs[i].byte) @try
                i = i + 1
            }
            at := app.active.cursor
            edit(app, at, at, lists::view<u8>(&literal)) @try
            continue
        }
        if input.kind == ChangeInputKind::Arrow {
            arrow(app, input.byte) @try
        } else {
            dispatch_key(app, input.byte) @try
        }
        i = i + 1
    }
    return nil
}

fn replay_change(app *App, change *Change) error {
    if change.visual_mode == Mode::VisualBlock {
        r := &buffer(app).text
        first := rope::line_at(r, app.active.cursor)
        last := first + min(change.lines - 1, rope::breaks(r.root) - first)
        column := cursor_column(r, app.active.cursor)
        right := column + max(1, change.columns) - 1
        app.mode = change.visual_mode
        app.visual_anchor = app.active.cursor
        app.visual_anchor_column = column
        app.active.cursor = column_offset(r, last, right)
        app.visual_column = right
        if app.active.cursor < line_end(r, app.active.cursor) {
            app.visual_column = cursor_column(r, app.active.cursor)
        }
        app.visual_wanted = app.visual_column
        app.visual_eol = change.eol
        return visual_key(app, change.command)
    }
    if change.visual_mode == Mode::VisualLine {
        r := &buffer(app).text
        first := rope::line_at(r, app.active.cursor)
        last := first + min(change.lines - 1, rope::breaks(r.root) - first)
        app.mode = change.visual_mode
        app.visual_anchor = rope::line_start(r, first)
        app.active.cursor = rope::line_start(r, last)
        return visual_key(app, change.command)
    }
    if change.visual_mode == Mode::VisualCharacter {
        r := &buffer(app).text
        start := app.active.cursor
        end := start
        if change.lines > 0 {
            line := rope::line_at(r, start)
            end = max(start, rope::line_start(r, line + min(change.lines, rope::breaks(r.root) - line)))
        }
        limit := line_end(r, end)
        remaining := change.points
        while remaining > 0 and end < limit {
            end = next_point(r, end)
            remaining = remaining - 1
        }
        app.mode = change.visual_mode
        app.visual_anchor = start
        app.active.cursor = start
        if end > start {
            app.active.cursor = previous_point(r, end)
        }
        return visual_key(app, change.command)
    }
    if change.command == KeyLowerS {
        return substitute_characters(app, change.count)
    }
    if change.command == KeyLowerD or change.command == KeyLowerC {
        if change.find.motion != 0 {
            return apply_character_find(app, change.find, change.find_repeated)
        }
        if change.object {
            return operator_word_object(app, change.command, change.around, change.count)
        }
        if change.motion == change.command {
            return operator_lines(app, change.command, change.count)
        }
        return operator_motion(app, change.command, change.motion, change.count)
    }
    return dispatch_key(app, change.command)
}
