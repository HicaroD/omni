package editor

use "std::terminal"
use "std::lists"
use "std::strings"
use "std::io"
use "vendor::platform"

fn run() error {
    platform::locale()
    argument u64 := 1
    while argument < platform::argc() {
        option := strings::from_c(platform::arg(argument))
        if option == "--help" or option == "-h" {
            io::println("Omni — a modal editor in Telia v0.3.0")
            io::println("Usage: omni [--root directory] [file ...]")
            io::println("Normal: i/a/o insert, Esc normal, :help commands, :q quit")
            io::println("Ctrl-p files, Ctrl-f project search, Ctrl-b buffers")
            return nil
        }
        if option == "--root" {
            if argument + 1 >= platform::argc() {
                return error("--root requires a directory")
            }
            if platform::root(platform::arg(argument + 1)) != 0 {
                return error("cannot change project root")
            }
            argument = argument + 1
        }
        argument = argument + 1
    }
    app := zero<App>()
    app.sync_updates = sync_supported()
    defer free_app(&app)
    app.root = new_pane() @try
    app.active = app.root
    open_buffer(&app, "") @try
    arg_index u64 := 1
    while arg_index < platform::argc() {
        arg := strings::from_c(platform::arg(arg_index))
        if arg == "--root" {
            arg_index = arg_index + 2
        } else {
            open_buffer(&app, arg) @try
            arg_index = arg_index + 1
        }
    }
    input := terminal::stdin()
    defer terminal::close(&input)
    output := terminal::stdout()
    defer terminal::close(&output)
    raw := terminal::apply_mode(&input, terminal::raw_mode()) @try
    defer terminal::restore(&raw)
    prepared := terminal::prepare_output(&output) @try
    defer terminal::restore(&prepared)
    caps := terminal::capabilities(&output) @try
    terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::AlternateScreen, enabled: true}, &caps) @try
    defer terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::AlternateScreen}, &caps)
    terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::BracketedPaste, enabled: true}, &caps) @try
    defer terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::BracketedPaste}, &caps)
    defer terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::CursorVisible, enabled: true}, &caps)
    defer terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::ResetStyle}, &caps)
    defer end_updates(&output, app.sync_updates)
    draw(&app, &output) @try
    bytes := zero<u8[4096]>()
    while app.quit == false {
        event := terminal::wait(&input, terminal::WaitOptions{input: true, resize: true, timeout_ms: 40}) @try
        if event.input {
            result := terminal::read(&input, bytes[:]) @try
            if result.eof {
                return nil
            }
            incoming := bytes[0:result.count] @try
            lists::append_slice<u8>(&app.input, incoming) @try
        }
        had_pending := lists::count<u8>(&app.input) > 0
        decode(&app, event.timed_out) @try
        poll_picker(&app.picker) @try
        if event.input or event.resized or app.picker.changed or had_pending {
            if app.quit == false {
                draw(&app, &output) @try
            }
        }
    }
    terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::ResetStyle}, &caps) @try
    terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::CursorVisible, enabled: true}, &caps) @try
    terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::BracketedPaste}, &caps) @try
    terminal::send_control(&output, terminal::Control{kind: terminal::ControlKind::AlternateScreen}, &caps) @try
    terminal::restore(&prepared) @try
    terminal::restore(&raw) @try
    return nil
}
