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
    if app.picker.kind != 0 or app.replace.open {
        if direction == 65 {
            return key(app, 11)
        }
        if direction == 66 {
            return key(app, 10)
        }
        return nil
    }
    if app.mode == 0 or app.mode == 1 {
        if direction == 65 {
            move(app, 107)
        }
        if direction == 66 {
            move(app, 106)
        }
        if direction == 67 {
            move(app, 108)
        }
        if direction == 68 {
            move(app, 104)
        }
        if direction == 72 {
            move(app, 48)
        }
        if direction == 70 {
            move(app, 36)
        }
    }
    return nil
}

fn finish_paste(app *App) error {
    if app.replace.open {
        field := &app.replace.query
        if app.replace.field {
            field = &app.replace.replacement
        }
        lists::append_slice<u8>(field, lists::view<u8>(&app.paste_data)) @try
        refresh_replace(app) @try
    } elif app.mode == 1 and app.picker.kind == 0 {
        app.group = app.group + 1
        edit(app, app.active.cursor, app.active.cursor, lists::view<u8>(&app.paste_data)) @try
        app.group = app.group + 1
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
            if first == 27 {
                marker u8[6] := .{27,91,50,48,49,126}
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
        } elif first == 27 {
            if len(bytes) == 1 {
                if expired {
                    key(app, 27) @try
                    consume(app, 1)
                } else {
                    break
                }
            } elif bytes[1] == 91 or bytes[1] == 79 {
                end u64 := 2
                while end < len(bytes) and (bytes[end] < 64 or bytes[end] > 126) {
                    end = end + 1
                }
                if end == len(bytes) {
                    if len(bytes) > 64 or expired {
                        consume(app, len(bytes))
                    } else {
                        break
                    }
                } else {
                    if end == 5 and bytes[2] == 50 and bytes[3] == 48 and bytes[4] == 48 and bytes[5] == 126 {
                        app.paste = true
                        lists::clear<u8>(&app.paste_data)
                    } else {
                        arrow(app, bytes[end]) @try
                    }
                    consume(app, end + 1)
                }
            } else {
                key(app, 27) @try
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
