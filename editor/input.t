package editor

use "std::lists"
use "pkg::rope"

fn consume(app *App, count u64) {
    app.input_at = app.input_at + count
}

fn compact_input(app *App) {
    bytes := lists::view<u8>(&app.input)
    remaining := len(bytes) - app.input_at
    i u64 := 0
    while i < remaining {
        bytes[i] = bytes[i + app.input_at]
        i = i + 1
    }
    while lists::count<u8>(&app.input) > remaining {
        lists::pop<u8>(&app.input)
    }
    app.input_at = 0
}

fn arrow(app *App, direction u8) error {
    cancel_mapping(app, true) @try
    record_change_input(app, ChangeInputKind::Arrow, direction) @try
    if app.change_active and app.mode != Mode::Insert {
        finish_change(app)
    }
    app.character_find = zero<CharacterFind>()
    app.pending = 0
    app.count = 0
    app.operator_count = 0
    app.text_object = 0
    if app.picker.kind != PickerKind::None {
        if direction == AnsiArrowUp {
            return key(app, KeyCtrlK)
        }
        if direction == AnsiArrowDown {
            return key(app, KeyCtrlJ)
        }
        return nil
    }
    motion u8 := 0
    if direction == AnsiArrowUp {
        motion = KeyLowerK
    } elif direction == AnsiArrowDown {
        motion = KeyLowerJ
    } elif direction == AnsiArrowRight {
        motion = KeyLowerL
    } elif direction == AnsiArrowLeft {
        motion = KeyLowerH
    } elif direction == AnsiHome {
        motion = KeyZero
    } elif direction == AnsiEnd {
        motion = KeyDollar
    }
    if visual(app) {
        return builtin_key(app, motion)
    }
    if app.mode == Mode::Normal or app.mode == Mode::Insert {
        if motion != 0 and app.block_insert {
            cancel_block_insert(app)
        }
        move(app, motion)
    }
    return nil
}

fn finish_paste(app *App) error {
    if app.mode == Mode::Insert and app.picker.kind == PickerKind::None {
        for byte in lists::view<u8>(&app.paste_data) {
            record_change_input(app, ChangeInputKind::Literal, byte) @try
        }
        if app.block_insert == false {
            app.group = app.group + 1
        }
        edit(app, app.active.cursor, app.active.cursor, lists::view<u8>(&app.paste_data)) @try
        if app.block_insert == false {
            app.group = app.group + 1
        }
    } else {
        app.message = "Paste ignored outside Insert mode"
    }
    lists::clear<u8>(&app.paste_data)
    app.paste = false
    return nil
}

fn decode(app *App, expired bool) error {
    while lists::count<u8>(&app.input) > app.input_at and app.quit == false {
        all := lists::view<u8>(&app.input)
        bytes := all[app.input_at:len(all)] @try
        first := bytes[0]
        if app.paste {
            if first == ByteEscape {
                marker u8[6] := .{ByteEscape,ByteLeftBracket,ByteTwo,ByteZero,ByteOne,ByteTilde}
                i u64 := 0
                same := true
                while i < min(len(bytes), 6) {
                    if bytes[i] != marker[i] {
                        same = false
                        break
                    }
                    i = i + 1
                }
                if same and len(bytes) < 6 {
                    break
                } elif same {
                    consume(app, 6)
                    finish_paste(app) @try
                } else {
                    lists::append<u8>(&app.paste_data, first) @try
                    consume(app, 1)
                }
            } else {
                lists::append<u8>(&app.paste_data, first) @try
                consume(app, 1)
            }
        } elif first == ByteEscape {
            if len(bytes) == 1 {
                if expired {
                    key(app, KeyEscape) @try
                    consume(app, 1)
                } else {
                    break
                }
            } elif bytes[1] == ByteLeftBracket or bytes[1] == ByteUpperO {
                end u64 := 2
                while end < len(bytes) and (bytes[end] < AnsiFinalFirst or bytes[end] > AnsiFinalLast) {
                    end = end + 1
                }
                if end == len(bytes) {
                    if len(bytes) > MaxEscapeBytes or expired {
                        consume(app, len(bytes))
                    } else {
                        break
                    }
                } else {
                    if end == 5 and bytes[2] == ByteTwo and bytes[3] == ByteZero and bytes[4] == ByteZero and bytes[5] == ByteTilde {
                        cancel_mapping(app, app.mode == Mode::Insert) @try
                        app.paste = true
                        lists::clear<u8>(&app.paste_data)
                    } else {
                        arrow(app, bytes[end]) @try
                    }
                    consume(app, end + 1)
                }
            } else {
                key(app, KeyEscape) @try
                consume(app, 1)
            }
        } else {
            key(app, first) @try
            consume(app, 1)
        }
    }
    compact_input(app)
    return nil
}
