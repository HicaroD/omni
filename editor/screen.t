package editor

use "std::lists"
use "std::terminal"
use "std::strings"
use "std::process"

struct RenderRow {
    current lists::List<u8>
    previous lists::List<u8>
    valid bool
}

fn free_row(row *RenderRow) {
    lists::free<u8>(&row.current)
    lists::free<u8>(&row.previous)
}

fn sync_supported() bool {
    setting, configured, setting_err := process::lookup_env("OMNI_SYNC_UPDATES")
    defer strings::free(&setting)
    if setting_err != nil {
        return false
    }
    if configured {
        return strings::view(&setting) == "1"
    }
    tmux, in_tmux, tmux_err := process::lookup_env("TMUX")
    defer strings::free(&tmux)
    if in_tmux or tmux_err != nil {
        return false
    }
    term, has_term, term_err := process::lookup_env("TERM")
    defer strings::free(&term)
    if has_term and term_err == nil {
        name := strings::view(&term)
        if name == "xterm-kitty" or name == "xterm-ghostty" {
            return true
        }
    }
    program, has_program, program_err := process::lookup_env("TERM_PROGRAM")
    defer strings::free(&program)
    if has_program and program_err == nil {
        name2 := strings::view(&program)
        return name2 == "WezTerm" or name2 == "ghostty"
    }
    return false
}

fn end_updates(output *terminal::Handle, enabled bool) error {
    if enabled {
        end u8[8] := .{27,91,63,50,48,50,54,108}
        return terminal::write_all(output, end[:])
    }
    return nil
}

fn begin_rows(app *App, width u64, height u64) error {
    while lists::count<RenderRow>(&app.rows) > height {
        old, found := lists::pop<RenderRow>(&app.rows)
        free_row(&old)
    }
    while lists::count<RenderRow>(&app.rows) < height {
        lists::append<RenderRow>(&app.rows, zero<RenderRow>()) @catch err {
            return err
        }
    }
    resized := width != app.screen_width or height != app.screen_height
    rows := lists::view<RenderRow>(&app.rows)
    i u64 := 0
    while i < len(rows) {
        row := &rows[i]
        lists::clear<u8>(&row.current)
        if resized {
            row.valid = false
        }
        i = i + 1
    }
    app.screen_width = width
    app.screen_height = height
    app.render_y = 0
    app.cursor_visible = false
    lists::clear<u8>(&app.frame)
    return nil
}

fn stash_row(app *App) error {
    if lists::count<u8>(&app.frame) > 0 {
        rows := lists::view<RenderRow>(&app.rows)
        row := &rows[app.render_y]
        lists::append_slice<u8>(&row.current, lists::view<u8>(&app.frame)) @catch err {
            return err
        }
        lists::clear<u8>(&app.frame)
    }
    return nil
}

fn position(app *App, x u64, y u64) error {
    stash_row(app) @catch err {
        return err
    }
    app.render_y = y
    app.render_x = x
    return cursor_position(&app.frame, x, y)
}

fn same_bytes(a u8[], b u8[]) bool {
    if len(a) != len(b) {
        return false
    }
    i u64 := 0
    while i < len(a) {
        if a[i] != b[i] {
            return false
        }
        i = i + 1
    }
    return true
}

fn row_changed(row *RenderRow) bool {
    if row.valid == false {
        return true
    }
    return same_bytes(lists::view<u8>(&row.current), lists::view<u8>(&row.previous)) == false
}

fn flush_rows(app *App, output *terminal::Handle) error {
    stash_row(app) @catch err {
        return err
    }
    rows := lists::view<RenderRow>(&app.rows)
    changed := false
    i u64 := 0
    while i < len(rows) {
        if row_changed(&rows[i]) {
            changed = true
        }
        i = i + 1
    }
    moved := app.cursor_known == false or app.cursor_x != app.last_cursor_x or app.cursor_y != app.last_cursor_y
    visibility := app.cursor_known == false or app.cursor_visible != app.cursor_shown
    update := changed or visibility or (app.cursor_visible and moved)
    if update and app.sync_updates {
        csi(&app.frame, "?2026h") @catch err {
            return err
        }
    }
    if visibility and app.cursor_visible == false {
        csi(&app.frame, "?25l") @catch err {
            return err
        }
    }
    i = 0
    while i < len(rows) {
        row := &rows[i]
        if row_changed(row) {
            lists::append_slice<u8>(&app.frame, lists::view<u8>(&row.current)) @catch err {
                return err
            }
        }
        i = i + 1
    }
    if app.cursor_visible and (changed or moved or visibility) {
        cursor_position(&app.frame, app.cursor_x, app.cursor_y) @catch err {
            return err
        }
    }
    if visibility and app.cursor_visible {
        csi(&app.frame, "?25h") @catch err {
            return err
        }
    }
    if update and app.sync_updates {
        csi(&app.frame, "?2026l") @catch err {
            return err
        }
    }
    terminal::write_all(output, lists::view<u8>(&app.frame)) @catch err {
        return err
    }
    i = 0
    while i < len(rows) {
        committed := &rows[i]
        previous := committed.previous
        committed.previous = committed.current
        committed.current = previous
        committed.valid = true
        i = i + 1
    }
    app.last_cursor_x = app.cursor_x
    app.last_cursor_y = app.cursor_y
    app.cursor_shown = app.cursor_visible
    app.cursor_known = true
    return nil
}
