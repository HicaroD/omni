"""Exercise the real editor in isolated controlling terminals, not the user's TTY."""
import fcntl
import os
from pathlib import Path
import pty
import select
import signal
import struct
import tempfile
import termios
import time
import unittest
import subprocess
import re
import unicodedata

BINARY = Path(os.environ.get("OMNI_BINARY", Path(__file__).resolve().parents[1] / "bin" / "omni")).resolve()


class Editor:
    def __init__(self, root, *files, env=None):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(root)
            os.environ["TERM"] = "xterm-256color"
            os.environ["OMNI_SYNC_UPDATES"] = "0"
            os.environ.update(env or {})
            os.execv(str(BINARY), [str(BINARY), *files])
        fcntl.ioctl(self.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 26, 100, 0, 0))
        os.set_blocking(self.fd, False)
        self.output = bytearray()
        self.status = None
        deadline = time.monotonic() + 5
        while b"\x1b[?25h" not in self.output and time.monotonic() < deadline:
            self.read(0.03)
        if b"\x1b[?25h" not in self.output:
            self.close()
            raise AssertionError(f"editor failed to start: {bytes(self.output)!r}")

    def read(self, duration=0.08):
        until = time.monotonic() + duration
        while time.monotonic() < until:
            ready, _, _ = select.select([self.fd], [], [], max(0, until - time.monotonic()))
            if ready:
                try:
                    chunk = os.read(self.fd, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                self.output.extend(chunk)
        return bytes(self.output)

    def send(self, keys, delay=0.08):
        pending = memoryview(keys.encode() if isinstance(keys, str) else keys)
        deadline = time.monotonic() + 5
        while pending:
            if time.monotonic() >= deadline:
                raise AssertionError("timed out sending input")
            readable, writable, _ = select.select([self.fd], [self.fd], [], 0.05)
            if readable:
                try:
                    self.output.extend(os.read(self.fd, 65536))
                except BlockingIOError:
                    pass
            if writable:
                try:
                    count = os.write(self.fd, pending[:4096])
                    pending = pending[count:]
                except BlockingIOError:
                    pass
        self.read(delay)

    def wait(self):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            self.read(0.02)
            pid, status = os.waitpid(self.pid, os.WNOHANG)
            if pid:
                self.status = status
                return os.waitstatus_to_exitcode(status)
        raise AssertionError(f"editor did not exit: {bytes(self.output[-1000:])!r}")

    def close(self):
        if self.status is None:
            try:
                os.kill(self.pid, signal.SIGKILL)
                os.waitpid(self.pid, 0)
            except ProcessLookupError:
                pass
        os.close(self.fd)


def screen_snapshot(output, width=100, height=26):
    """Small ANSI screen model for visual regression checks, including styles."""
    cells = [[(" ", False) for _ in range(width)] for _ in range(height)]
    text = output.decode("utf-8", errors="replace")
    x = y = 0
    reverse = wrap = False
    i = 0
    while i < len(text):
        if text[i] == "\x1b":
            control = re.match(r"\x1b\[([0-9;?]*)([A-Za-z~])", text[i:])
            if not control:
                raise AssertionError(f"unrecognized terminal sequence: {text[i:i + 30]!r}")
            args, kind = control.groups()
            if kind == "H":
                row, column = (int(part) for part in args.split(";"))
                y, x, wrap = row - 1, column - 1, False
            elif kind == "m":
                reverse = args == "7"
            elif kind == "J" and args == "2":
                raise AssertionError("ordinary rendering must not clear the screen")
            i += len(control.group())
            continue
        char = text[i]
        if unicodedata.combining(char):
            i += 1
            continue
        if wrap:
            y, x, wrap = min(y + 1, height - 1), 0, False
        if not (0 <= y < height and 0 <= x < width):
            raise AssertionError(f"render outside viewport at {x}, {y}")
        cells[y][x] = char, reverse
        count = 2 if unicodedata.east_asian_width(char) in ("W", "F") else 1
        x += count
        if x >= width:
            x, wrap = width - 1, True
        i += 1
    return cells


class TerminalTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omni-tests-")
        self.root = Path(self.temp.name)
        self.editor = None

    def tearDown(self):
        if self.editor:
            self.editor.close()
        self.temp.cleanup()

    def start(self, *files, env=None):
        self.editor = Editor(self.root, *files, env=env)
        return self.editor

    def test_insert_save_and_terminal_cleanup(self):
        e = self.start()
        e.send("iHello, Telia!\rsecond line")
        e.send(b"\x1b")
        e.send(":w greeting.t\r:q\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "greeting.t").read_bytes(), b"Hello, Telia!\nsecond line")
        self.assertIn(b"\x1b[?1049l", e.output)
        self.assertIn(b"\x1b[?2004l", e.output)
        self.assertIn(b"\x1b[?25h", e.output)
        restored = termios.tcgetattr(e.fd)
        self.assertTrue(restored[3] & termios.ECHO)
        self.assertTrue(restored[3] & termios.ICANON)
        self.assertTrue(restored[3] & termios.ISIG)

    def test_undo_redo_and_dirty_guard(self):
        (self.root / "file.t").write_text("original\n")
        e = self.start("file.t")
        e.send("iadded ")
        e.send(b"\x1b")
        e.send(":q\r")
        self.assertIn(b"Unsaved changes", e.output)
        e.send("u")
        e.send(b"\x12")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "file.t").read_text(), "added original\n")

    def test_splits_shared_document_and_multiple_files(self):
        (self.root / "one.t").write_text("one\n")
        (self.root / "two.t").write_text("two\n")
        e = self.start("one.t")
        e.send(":vsplit\r")
        e.send("iX")
        e.send(b"\x1b")
        e.send(b"\x17h")
        e.send(":w\r:split two.t\r")
        e.send("iY")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "one.t").read_text(), "Xone\n")
        self.assertEqual((self.root / "two.t").read_text(), "Ytwo\n")

    def test_fragmented_paste_and_unicode(self):
        e = self.start()
        e.send(b"i\x1b[20", 0.01)
        e.send(b"0~")
        payload = "héllo 界 e\u0301\n:q!\n".encode()
        e.send(payload)
        e.send(b"\x1b[201", 0.01)
        e.send(b"~")
        e.send(b"\x1b")
        e.send(":w unicode.t\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "unicode.t").read_bytes(), payload)

    def test_file_picker_and_project_search(self):
        (self.root / "target.t").write_text("needle\nsecond\n")
        (self.root / "other.t").write_text("other\n")
        e = self.start()
        e.send(b"\x10")
        e.send("targ", 0.2)
        self.assertIn(b"target.t", e.output)
        e.send(b"\r")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":w\r:grep second\r", 0.3)
        self.assertIn(b"target.t:2:1:second", e.output)
        e.send(b"\r")
        e.send("iY")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "target.t").read_text(), "Xneedle\nYsecond\n")

    def test_fragmented_arrow_and_resize(self):
        e = self.start()
        e.send("iab")
        e.send(b"\x1b[", 0.01)
        e.send(b"D")
        e.send("X")
        fcntl.ioctl(e.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 15, 45, 0, 0))
        e.read(0.1)
        e.send(b"\x1b")
        e.send(":w arrows.t\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "arrows.t").read_text(), "aXb")

    def test_buffer_switch_restores_cursor_and_search_wraps(self):
        (self.root / "one.t").write_text("one\nsecond\nthird\n")
        (self.root / "two.t").write_text("two\n")
        e = self.start("one.t", "two.t")
        e.send(":bp\rj:e two.t\r:b#\riX")
        e.send(b"\x1b")
        e.send("/third\riY")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "one.t").read_text(), "one\nXsecond\nYthird\n")

    def test_save_refuses_external_changes(self):
        path = self.root / "file.t"
        path.write_text("original")
        e = self.start("file.t")
        e.send("iX")
        e.send(b"\x1b")
        path.write_text("external edit")
        e.send(":w\r")
        self.assertIn(b"Save refused", e.output)
        e.send(":qa!\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "external edit")

    def test_existing_destination_and_failed_save_preserve_data(self):
        path = self.root / "existing.t"
        path.write_text("keep me")
        e = self.start()
        e.send("inew")
        e.send(b"\x1b")
        e.send(":w existing.t\r")
        self.assertIn(b"Save refused", e.output)
        e.send(":w missing/directory/file.t\r")
        self.assertIn(b"Cannot resolve save destination", e.output)
        e.send(":qa!\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "keep me")

    def test_canonical_paths_reuse_unsaved_buffer(self):
        path = self.root / "same.t"
        path.write_text("original\n")
        e = self.start("same.t")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":e ./same.t\r:w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "Xoriginal\n")

    def test_yank_paste_delete_and_undo(self):
        path = self.root / "lines.t"
        path.write_text("one\ntwo\nthree\n")
        e = self.start("lines.t")
        e.send("yypdd")
        e.send("u")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "one\none\ntwo\nthree\n")

    def test_control_bytes_and_invalid_utf8_are_not_executed(self):
        path = self.root / "bytes.t"
        original = b"a\x1b[2J\x00\xff\xc0\xaf\n"
        path.write_bytes(original)
        e = self.start("bytes.t")
        self.assertIn(b"a?[2J????", e.output)
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_bytes(), original)

    def test_regex_and_hidden_file_toggles(self):
        (self.root / ".hidden.t").write_text("Needle42\n")
        e = self.start()
        e.send(":grep Needle[0-9]+\r", 0.15)
        e.send(b"\x08\x12", 0.2)
        self.assertIn(b".hidden.t:1:1:Needle42", e.output)
        e.send(b"\r")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / ".hidden.t").read_text(), "XNeedle42\n")

    def test_split_close_buffer_delete_and_resize(self):
        (self.root / "one.t").write_text("one\n")
        (self.root / "two.t").write_text("two\n")
        e = self.start("one.t", "two.t")
        e.send(":vsplit\r:split\r")
        e.send(b"\x17+\x17-\x17>\x17<\x17=")
        e.send(":q\r:bd\r")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":w third.t\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "third.t").read_text(), "X")

    def test_explicit_project_root(self):
        project = self.root / "project"
        project.mkdir()
        (project / "file.t").write_text("hello\n")
        e = self.start("--root", "project", "file.t")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((project / "file.t").read_text(), "Xhello\n")

    def test_save_through_symlink_preserves_link_and_permissions(self):
        path = self.root / "real.t"
        path.write_text("hello\n")
        path.chmod(0o640)
        link = self.root / "link.t"
        link.symlink_to("real.t")
        e = self.start("link.t")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertTrue(link.is_symlink())
        self.assertEqual(path.stat().st_mode & 0o777, 0o640)
        self.assertEqual(path.read_text(), "Xhello\n")

    def test_large_paste_is_one_undo_unit(self):
        e = self.start()
        e.send(b"i\x1b[200~" + b"line\n" * 12000 + b"\x1b[201~", 0.2)
        e.send(b"\x1b")
        e.send("u:w empty.t\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "empty.t").read_bytes(), b"")

    def test_undo_branch_discards_redo(self):
        e = self.start()
        e.send("iold")
        e.send(b"\x1b")
        e.send("uiNEW")
        e.send(b"\x1b")
        e.send(b"\x12:w branch.t\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "branch.t").read_text(), "NEW")

    def test_help_works_without_terminal(self):
        result = subprocess.run([str(BINARY), "--help"], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertIn(b"Usage: omni", result.stdout)

    def test_redraw_changes_only_affected_rows_without_cursor_blink(self):
        (self.root / "file.t").write_text("first line\nuntouched second line\n")
        e = self.start("file.t")
        self.assertNotIn(b"\x1b[2J", e.output)
        e.output.clear()
        e.send("iX")
        self.assertIn(b"Xfirst line", e.output)
        self.assertNotIn(b"untouched second line", e.output)
        self.assertNotIn(b"\x1b[?25l", e.output)
        self.assertNotIn(b"\x1b[?25h", e.output)
        self.assertNotIn(b"\x1b[2J", e.output)
        e.send(b"\x1b")
        e.output.clear()
        e.send("h")
        self.assertNotIn(b"first line", e.output)
        self.assertLess(len(e.output), 200)
        e.send(":qa!\r")
        self.assertEqual(e.wait(), 0)

    def test_unchanged_input_and_idle_emit_no_frame(self):
        e = self.start()
        e.output.clear()
        e.send("h")
        self.assertEqual(e.output, b"")
        e.read(0.2)
        self.assertEqual(e.output, b"")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_picker_close_restores_screen_and_cursor_once(self):
        (self.root / "file.t").write_text("original document\nsecond line\n")
        e = self.start("file.t")
        before = screen_snapshot(e.output)
        mark = len(e.output)
        e.send(b"\x10", 0.2)
        e.send("file")
        e.send(b"\x1b")
        self.assertEqual(screen_snapshot(e.output), before)
        changes = e.output[mark:]
        self.assertEqual(changes.count(b"\x1b[?25l"), 1)
        self.assertEqual(changes.count(b"\x1b[?25h"), 1)
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_split_close_erases_divider_and_restores_styles(self):
        (self.root / "file.t").write_text("original document\nsecond line\n")
        e = self.start("file.t")
        before = screen_snapshot(e.output)
        e.send(":vsplit\r")
        split = screen_snapshot(e.output)
        self.assertNotEqual(split, before)
        self.assertIn(("|", False), split[0])
        e.send(":q\r")
        self.assertEqual(screen_snapshot(e.output), before)
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_resize_invalidates_rows_even_after_tiny_viewport(self):
        (self.root / "file.t").write_text("original document\nsecond line\n")
        e = self.start("file.t")
        before = screen_snapshot(e.output)
        fcntl.ioctl(e.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 15, 45, 0, 0))
        mark = len(e.output)
        e.read(0.15)
        smaller = screen_snapshot(e.output[mark:], 45, 15)
        self.assertEqual("".join(char for char, _ in smaller[0]).rstrip(), "original document")
        fcntl.ioctl(e.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 2, 2, 0, 0))
        e.read(0.15)
        mark = len(e.output)
        fcntl.ioctl(e.fd, termios.TIOCSWINSZ, struct.pack("HHHH", 26, 100, 0, 0))
        e.read(0.15)
        self.assertEqual(screen_snapshot(e.output[mark:]), before)
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_synchronized_updates_are_balanced_and_optional(self):
        e = self.start(env={"OMNI_SYNC_UPDATES": "1"})
        e.send("iX")
        e.send(b"\x1b")
        self.assertGreater(e.output.count(b"\x1b[?2026h"), 0)
        self.assertEqual(e.output.count(b"\x1b[?2026h"), e.output.count(b"\x1b[?2026l"))
        self.assertNotIn(b"\x1b[2J", e.output)
        e.send(":qa!\r")
        self.assertEqual(e.wait(), 0)

    def test_waiting_picker_does_not_repaint_without_new_results(self):
        (self.root / "file.t").write_text("preview\n")
        tools = self.root / "tools"
        tools.mkdir()
        rg = tools / "rg"
        rg.write_text("#!/bin/sh\nsleep 0.5\nprintf 'file.t\\0'\nsleep 0.3\n")
        rg.chmod(0o755)
        e = self.start(env={"PATH": str(tools) + os.pathsep + os.environ["PATH"]})
        e.send(b"\x10")
        e.output.clear()
        e.read(0.15)
        self.assertEqual(e.output, b"")
        deadline = time.monotonic() + 3
        while b"Literal / smart case" not in e.output and time.monotonic() < deadline:
            e.read(0.05)
        self.assertIn(b"Literal / smart case", e.output)
        self.assertIn(b"file.t", e.output)
        e.output.clear()
        e.read(0.15)
        self.assertEqual(e.output, b"")
        e.send(b"\x1b")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)


if __name__ == "__main__":
    unittest.main()
