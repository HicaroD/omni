package editor

use "std::process"
use "std::lists"
use "std::strings"
use "std::memory"
use "std::terminal"

fn spawn_search(kind i32, query string, hidden bool, ignored bool, regex bool) (process::Child, error) {
    args := lists::create<string>()
    defer lists::free<string>(&args)
    if kind == 0 {
        lists::append<string>(&args, "--files") @try
        lists::append<string>(&args, "-0") @try
    } else {
        fixed string[6] := .{"--line-number", "--column", "--no-heading", "--color=never", "--smart-case", "--null"}
        lists::append_slice<string>(&args, fixed[:]) @try
        if regex == false {
            lists::append<string>(&args, "--fixed-strings") @try
        }
    }
    if hidden {
        lists::append<string>(&args, "--hidden") @try
    }
    if ignored {
        lists::append<string>(&args, "--no-ignore") @try
    }
    if kind == 0 or hidden {
        lists::append<string>(&args, "-g") @try
        lists::append<string>(&args, "!.git") @try
    }
    if kind != 0 {
        lists::append<string>(&args, "--") @try
        lists::append<string>(&args, query) @try
        lists::append<string>(&args, ".") @try
    }
    return process::spawn("rg", lists::view<string>(&args), process::SpawnOptions{pipe_stdout: true, pipe_stderr: true})
}

// Bound work per frame, discard diagnostics, and distinguish EOF from process exit.
fn poll_search(child *process::Child, buffer u8[]) (u64, i32) {
    count, eof, blocked, read_err := process::read_stdout(child, buffer)
    discard := zero<u8[8192]>()
    ignored, stderr_eof, stderr_blocked, stderr_err := process::read_stderr(child, discard[:])
    if read_err != nil or stderr_err != nil {
        return count, -1
    }
    status, done, wait_err := process::poll(child)
    if wait_err != nil {
        return count, -1
    }
    if eof and stderr_eof and done {
        if status.signal != 0 or status.code > 1 {
            return count, -1
        }
        return count, 1
    }
    return count, 0
}

// Clipboard operations are synchronous, but pipe backpressure must not busy-wait.
fn clipboard_pause() error {
    input := terminal::stdin()
    defer terminal::close(&input)
    terminal::wait(&input, terminal::WaitOptions{resize: true, timeout_ms: 10}) @try
    return nil
}

fn copy_clipboard(bytes u8[]) error {
    text := strings::from_bytes(bytes) @try
    defer strings::free(&text)
    args := zero<string[0]>()
    child := process::spawn("pbcopy", args[:], process::SpawnOptions{pipe_stdin: true, pipe_stdout: true, pipe_stderr: true}) @try
    defer process::close_child(&child)
    at u64 := 0
    closed := false
    buffer := zero<u8[8192]>()
    while true {
        progress := false
        if closed == false {
            part := strings::slice(strings::view(&text), at, strings::len(strings::view(&text))) @try
            count, blocked := process::write_stdin(&child, part) @try
            at = at + count
            progress = count > 0
            if at == strings::len(strings::view(&text)) {
                process::close_stdin(&child) @try
                closed = true
            }
        }
        count_out, eof_out, blocked_out := process::read_stdout(&child, buffer[:]) @try
        count_err, eof_err, blocked_err := process::read_stderr(&child, buffer[:]) @try
        status, done := process::poll(&child) @try
        if done and eof_out and eof_err {
            if closed == false or status.code != 0 or status.signal != 0 {
                return error("pbcopy failed")
            }
            return process::close_child(&child)
        }
        if progress == false and count_out == 0 and count_err == 0 {
            clipboard_pause() @try
        }
    }
    return nil
}

fn read_system_clipboard() (lists::List<u8>, error) {
    bytes := lists::create<u8>()
    defer lists::free<u8>(&bytes)
    args := zero<string[0]>()
    child := process::spawn("pbpaste", args[:], process::SpawnOptions{pipe_stdin: true, pipe_stdout: true, pipe_stderr: true}) @try
    defer process::close_child(&child)
    process::close_stdin(&child) @try
    buffer := zero<u8[8192]>()
    while true {
        count, eof, blocked := process::read_stdout(&child, buffer[:]) @try
        part := buffer[0:count] @try
        lists::append_slice<u8>(&bytes, part) @try
        count_err, eof_err, blocked_err := process::read_stderr(&child, buffer[:]) @try
        status, done := process::poll(&child) @try
        if done and eof and eof_err {
            if status.code != 0 or status.signal != 0 {
                return zero<lists::List<u8>>(), error("pbpaste failed")
            }
            process::close_child(&child) @try
            return memory::take<lists::List<u8>>(&bytes), nil
        }
        if count == 0 and count_err == 0 {
            clipboard_pause() @try
        }
    }
    return zero<lists::List<u8>>(), nil
}
