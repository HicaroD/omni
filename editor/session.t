package editor

use "std::terminal"
use "std::lists"
use "std::strings"
use "std::io"
use "std::process"

fn run() error {
    args := process::args() @try
    defer process::free(&args)
    config_name := ""
    no_config := false
    argument u64 := 0
    while argument < process::count(&args) {
        option := process::get(&args, argument) @try
        if option == "--help" or option == "-h" {
            io::println("Omni — a modal editor in Telia v0.3.2")
            io::println("Usage: omni [--root directory] [--config path | --no-config] [file ...]")
            io::println("Normal: i/a/o insert, Esc normal, :help commands, :q quit")
            io::println("Ctrl-p files, Ctrl-f project search, Ctrl-b buffers")
            return nil
        }
        if option == "--root" {
            if argument + 1 >= process::count(&args) {
                return error("--root requires a directory")
            }
            root := process::get(&args, argument + 1) @try
            process::chdir(root) @catch err {
                return error("cannot change project root")
            }
            argument = argument + 1
        } elif option == "--config" {
            if argument + 1 >= process::count(&args) {
                return error("--config requires a path")
            }
            chosen := process::get(&args, argument + 1) @try
            config_name = chosen
            if config_name == "" {
                return error("--config requires a nonempty path")
            }
            argument = argument + 1
        } elif option == "--no-config" {
            no_config = true
        }
        argument = argument + 1
    }
    app := zero<App>()
    app.sync_updates = sync_supported()
    defer free_app(&app)
    if no_config and config_name != "" {
        return error("--config and --no-config cannot be combined")
    }
    load_config(&app, config_name, no_config) @try
    app.root = new_pane() @try
    app.active = app.root
    open_buffer(&app, "") @try
    arg_index u64 := 0
    while arg_index < process::count(&args) {
        arg := process::get(&args, arg_index) @try
        if arg == "--root" or arg == "--config" {
            arg_index = arg_index + 2
        } elif arg == "--no-config" {
            arg_index = arg_index + 1
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
        mappings_changed := expire_mappings(&app, monotonic_ms()) @try
        decode(&app, event.timed_out) @try
        poll_picker(&app.picker) @try
        if event.input or event.resized or app.picker.changed or had_pending or mappings_changed {
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
