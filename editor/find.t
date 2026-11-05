package editor

use "pkg::rope"

struct CharacterFind {
    motion u8
    operator u8
    count u64
    target u32
    remaining u64
    minimum u32
}

fn character_find_motion(byte u8) bool {
    return byte == KeyLowerF or byte == KeyUpperF or byte == KeyLowerT or byte == KeyUpperT
}

fn finish_character_find(app *App, byte u8) error {
    request := app.character_find
    app.character_find = zero<CharacterFind>()
    if request.remaining == 0 {
        if byte < 128 {
            if (byte < ByteSpace and byte != ByteTab) or byte == KeyDelete {
                return nil
            }
            request.target = widen<u32>(byte)
        } elif byte >= 194 and byte <= 223 {
            request.target = widen<u32>(byte - 192)
            request.remaining = 1
            request.minimum = 128
        } elif byte >= 224 and byte <= 239 {
            request.target = widen<u32>(byte - 224)
            request.remaining = 2
            request.minimum = 2048
        } elif byte >= 240 and byte <= 244 {
            request.target = widen<u32>(byte - 240)
            request.remaining = 3
            request.minimum = 65536
        } else {
            return nil
        }
    } else {
        if byte < 128 or byte >= 192 {
            return nil
        }
        request.target = request.target * 64 + widen<u32>(byte - 128)
        request.remaining = request.remaining - 1
    }
    if request.remaining > 0 {
        app.character_find = request
        return nil
    }
    if request.target < request.minimum or request.target > 1114111 or (request.target >= 55296 and request.target <= 57343) {
        return nil
    }
    app.last_character_find = request
    app.last_character_find.operator = 0
    return apply_character_find(app, request, false)
}

fn repeat_character_find(app *App, reverse bool, count u64, operator u8) error {
    request := app.last_character_find
    if request.motion == 0 {
        return nil
    }
    request.count = count
    request.operator = operator
    if reverse {
        if request.motion == KeyLowerF {
            request.motion = KeyUpperF
        } elif request.motion == KeyUpperF {
            request.motion = KeyLowerF
        } elif request.motion == KeyLowerT {
            request.motion = KeyUpperT
        } else {
            request.motion = KeyLowerT
        }
    }
    return apply_character_find(app, request, true)
}

fn apply_character_find(app *App, request CharacterFind, repeated bool) error {
    r := &buffer(app).text
    end := line_end(r, app.active.cursor)
    start := rope::line_start(r, rope::line_at(r, app.active.cursor))
    at := app.active.cursor
    backward := request.motion == KeyUpperF or request.motion == KeyUpperT
    remaining := request.count
    while (backward and at > start) or (backward == false and at < end) {
        if backward {
            at = previous_point(r, at)
        } else {
            at = next_point(r, at)
            if at >= end {
                break
            }
        }
        cp, length := point(r, at)
        // point() renders invalid UTF-8 as '?'; find must match real text only.
        if cp == request.target and (cp != CodePointQuestion or rope::byte(r, at) == ByteQuestion) {
            if repeated and ((request.motion == KeyLowerT and previous_point(r, at) == app.active.cursor) or (request.motion == KeyUpperT and next_point(r, at) == app.active.cursor)) {
                continue
            }
            remaining = remaining - 1
            if remaining == 0 {
                destination := at
                if request.motion == KeyLowerT {
                    destination = previous_point(r, at)
                } elif request.motion == KeyUpperT {
                    destination = next_point(r, at)
                }
                if request.operator != 0 {
                    origin := app.active.cursor
                    if backward {
                        if destination == origin {
                            return nil
                        }
                        return operate_range(app, request.operator, destination, origin, false)
                    }
                    return operate_range(app, request.operator, origin, next_point(r, destination), false)
                }
                app.active.cursor = destination
                if app.mode == Mode::VisualBlock {
                    app.visual_column = cursor_column(r, destination)
                    app.visual_wanted = app.visual_column
                    app.visual_eol = false
                }
                return nil
            }
        }
    }
    app.message = "Character not found"
    return nil
}
