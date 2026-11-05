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
import sys

BINARY = Path(os.environ.get("OMNI_BINARY", Path(__file__).resolve().parents[1] / "bin" / "omni")).resolve()


class Editor:
    def __init__(self, root, *files, env=None):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(root)
            os.environ["TERM"] = "xterm-256color"
            os.environ["OMNI_SYNC_UPDATES"] = "0"
            os.environ["XDG_CONFIG_HOME"] = str(Path(root) / ".config")
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

    def expect(self, text):
        deadline = time.monotonic() + 3
        while text not in self.output and time.monotonic() < deadline:
            self.read(0.03)
        if text not in self.output:
            raise AssertionError(f"missing {text!r}: {bytes(self.output[-1000:])!r}")

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
    def write_config(self, source):
        path = self.root / ".config" / "omni" / "config.toml"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(source)
        return path

    def test_invalid_config_reports_file_and_line_before_entering_terminal_mode(self):
        cases = [
            ("[keys]\nleader = 'unterminated\n", 2),
            ("[keys.normal]\nx = 'action:typo'\n", 2),
            ("# heading\n[unknown]\nx = 'l'\n", 2),
        ]
        for source, line in cases:
            with self.subTest(source=source):
                config = self.write_config(source)
                result = subprocess.run([str(BINARY), "--config", str(config)],
                                        cwd=self.root, capture_output=True, timeout=5)
                output = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"Configuration error: {config}:{line}".encode(), output)
                self.assertNotIn(b"\x1b", output)

    def test_explicit_config_overrides_discovery_and_no_config_bypasses_it(self):
        self.write_config("invalid = [\n")
        custom = self.root / "custom config.toml"
        custom.write_text("[keys.normal]\nQ = 'action:quit'\n")
        e = self.start("--config", "custom config.toml")
        e.send("Q")
        self.assertEqual(e.wait(), 0)
        e.close()
        self.editor = None
        e = self.start("--no-config")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_config_falls_back_to_home_when_xdg_is_empty(self):
        home = self.root / "home"
        config = home / ".config" / "omni" / "config.toml"
        config.parent.mkdir(parents=True)
        config.write_text("[keys.normal]\nQ = 'action:quit'\n")
        e = self.start(env={"HOME": str(home), "XDG_CONFIG_HOME": ""})
        e.send("Q")
        self.assertEqual(e.wait(), 0)

    def test_timeout_runs_a_shorter_mapping_and_flushes_unmatched_insert_text(self):
        self.write_config("[keys]\ntimeout_ms = 150\n[keys.normal]\ng = 'l'\ngg = '$'\n"
                          "[keys.insert]\njk = '<Esc>'\n")
        target = self.root / "doc.txt"
        target.write_text("abc")
        e = self.start("doc.txt")
        e.send("g", delay=0.03)
        e.read(0.3)
        e.send("xij", delay=0.03)
        e.read(0.3)
        e.send(b"\x1b")
        e.send(":wq\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "ajc")

    def test_insert_mapping_prefix_and_bracketed_paste_remain_literal(self):
        self.write_config("[keys.insert]\njk = '<Esc>'\n")
        target = self.root / "doc.txt"
        target.write_text("")
        e = self.start("doc.txt")
        e.send(b"ij\x1b[200~jk\x1b[201~\x1b")
        e.send(":wq\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "jjk")

    def test_leader_prefix_is_shown_then_times_out_to_comma_find_repeat(self):
        config = self.root / ".config" / "omni" / "config.toml"
        config.parent.mkdir(parents=True)
        config.write_text("[keys]\ntimeout_ms = 200\n[keys.normal]\n'<leader>x' = '0'\n")
        target = self.root / "doc.txt"
        target.write_text("a(b)c(d)")
        e = self.start("doc.txt")
        e.send("f)f)")
        e.send(",", delay=0.03)
        screen = screen_snapshot(e.output)
        self.assertIn("Keys: ,", "".join(char for char, _ in screen[-1]))
        e.read(0.4)
        screen = screen_snapshot(e.output)
        self.assertNotIn("Keys:", "".join(char for char, _ in screen[-1]))
        e.send("x:wq\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "a(bc(d)")

    def test_space_leader_is_visible_in_pending_key_display(self):
        self.write_config("[keys]\nleader = '<Space>'\ntimeout_ms = 200\n"
                          "[keys.normal]\n'<leader>x' = '0'\n")
        e = self.start()
        e.send(" ", delay=0.03)
        screen = screen_snapshot(e.output)
        self.assertIn("Keys: <Space>", "".join(char for char, _ in screen[-1]))
        e.send(b"\x1b")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_configuration_loads_from_xdg_and_drives_insert_and_named_action_mappings(self):
        config = self.root / ".config" / "omni" / "config.toml"
        config.parent.mkdir(parents=True)
        config.write_text("[keys]\nleader = '!'\n[keys.normal]\n"
                          "'<leader>w' = 'action:write'\n'<leader>q' = 'action:quit'\n"
                          "[keys.insert]\njk = '<Esc>'\n")
        target = self.root / "doc.txt"
        target.write_text("abc")
        e = self.start("doc.txt")
        e.send("iNEWjk!w")
        self.assertEqual(target.read_text(), "NEWabc")
        e.send("!q")
        self.assertEqual(e.wait(), 0)

    def test_character_find_accepts_fragmented_utf8_and_change_undo_redo(self):
        original = "a界b界c界d界end\nnext"
        target = self.root / "find.txt"
        target.write_text(original)
        e = self.start("find.txt")
        e.send("2c2f")
        for byte in "界".encode():
            e.send(bytes([byte]))
        e.send("NEW")
        e.send(b"\x1b")
        e.send(":w\r")
        self.assertEqual(target.read_text(), "NEWend\nnext")
        e.send("u:w\r")
        self.assertEqual(target.read_text(), original)
        e.send(b"\x12:wq\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "NEWend\nnext")

    def test_character_find_operator_ranges_and_repeats_through_real_input(self):
        original = "a(b)c(d)!"
        cases = [
            ("df)", "c(d)!"),
            ("dt)", ")c(d)!"),
            ("f!dF(", "a(b)c!"),
            ("f!dT(", "a(b)c(!"),
            ("f)d;", "a(b!"),
            ("2f)d,", "a(b)!"),
        ]
        target = self.root / "find.txt"
        for keys, expected in cases:
            with self.subTest(keys=keys):
                target.write_text(original)
                e = self.start("find.txt")
                e.send(keys + ":w\r")
                self.assertEqual(target.read_text(), expected)
                e.send("u:wq\r")
                self.assertEqual(e.wait(), 0)
                self.assertEqual(target.read_text(), original)
                e.close()
                self.editor = None

    def test_visual_find_repeat_updates_highlighting_at_unicode_boundaries(self):
        target = self.root / "find.txt"
        target.write_text("aé界x界!")
        e = self.start("find.txt")
        e.send("vt界")
        screen = screen_snapshot(e.output)
        self.assertEqual([screen[0][x][1] for x in [0, 1, 2, 4, 5]],
                         [True, True, False, False, False])
        e.send(";")
        screen = screen_snapshot(e.output)
        self.assertEqual([screen[0][x][1] for x in [0, 1, 2, 4, 5]],
                         [True, True, True, True, False])
        e.send("d:wq\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "界!")

    def test_arrow_cancels_pending_find_before_a_later_edit(self):
        target = self.root / "find.txt"
        target.write_text("abxc")
        e = self.start("find.txt")
        e.send(b"df\x1b[Cx:wq\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "axc")

    def test_insert_shortcuts_save_undo_and_redo_through_real_input(self):
        original = " \t世界 tail\nnext"
        cases = [
            ("I!", " \t!世界 tail\nnext"),
            ("A!", " \t世界 tail!\nnext"),
            ("O!", " \t!\n \t世界 tail\nnext"),
            ("2ls!", " \t!界 tail\nnext"),
            ("2lC!", " \t!\nnext"),
        ]
        target = self.root / "insert.txt"
        for keys, expected in cases:
            with self.subTest(keys=keys):
                target.write_text(original)
                e = self.start("insert.txt")
                e.send(keys)
                e.send(b"\x1b")
                e.send(":w\r")
                self.assertEqual(target.read_text(), expected)
                e.send("u:w\r")
                self.assertEqual(target.read_text(), original)
                e.send(b"\x12:wq\r")
                self.assertEqual(e.wait(), 0)
                self.assertEqual(target.read_text(), expected)
                e.close()
                self.editor = None

    def test_counted_substitute_clamps_to_line_end_and_yanks_whole_characters(self):
        target = self.root / "substitute.txt"
        target.write_text("é世\nnext")
        e = self.start("substitute.txt")
        e.send("9" * 40 + "s!")
        e.send(b"\x1b")
        e.send(":w\r")
        self.assertEqual(target.read_text(), "!\nnext")
        e.send("0p:wq\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "!é世\nnext")

    def test_counted_operators_and_word_objects_save_and_undo_through_real_input(self):
        original = "one two three\n世界 next\nlast"
        target = self.root / "motions.txt"
        target.write_text(original)
        e = self.start("motions.txt")
        e.send("d2w:w\r")
        self.assertEqual(target.read_text(), "three\n世界 next\nlast")
        e.send("j0lciwnew")
        e.send(b"\x1b")
        e.send(":w\r")
        self.assertEqual(target.read_text(), "three\nnew next\nlast")
        e.send("u:w\r")
        self.assertEqual(target.read_text(), "three\n世界 next\nlast")
        e.send("u:w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), original)

    def test_overflowing_counts_are_bounded_by_available_text(self):
        target = self.root / "counts.txt"
        target.write_text("one\ntwo\nthree")
        e = self.start("counts.txt")
        e.send("9" * 40 + "d" + "9" * 40 + "d:w\r")
        self.assertEqual(target.read_text(), "")
        e.send("u" + "9" * 40 + "jdd:w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(target.read_text(), "one\ntwo")

    def test_visual_highlight_is_confined_to_active_split_and_clears_after_yank(self):
        (self.root / "split.txt").write_text("abcd\nefgh")
        e = self.start("split.txt")
        e.send(":vsplit\rvl")
        screen = screen_snapshot(e.output)
        self.assertFalse(any(reverse for _, reverse in screen[0][:49]))
        self.assertEqual([reverse for _, reverse in screen[0][50:54]], [True, True, False, False])
        e.send("y")
        screen = screen_snapshot(e.output)
        self.assertFalse(any(reverse for _, reverse in screen[0]))
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_moving_during_block_insert_cancels_replication(self):
        (self.root / "block.txt").write_text("abcd\nefgh")
        e = self.start("block.txt")
        e.send(b"l\x16jI!\x1b[C\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "block.txt").read_text(), "a!bcd\nefgh")

    def test_block_change_with_bracketed_paste_is_one_undo_unit(self):
        original = "abcd\nefgh\nijkl"
        (self.root / "block.txt").write_text(original)
        e = self.start("block.txt")
        e.send(b"l\x16ljjc\x1b[200~XY\x1b[201~\x1b")
        e.send(":w\r")
        self.assertEqual((self.root / "block.txt").read_text(), "aXYd\neXYh\niXYl")
        e.send("u:w\r")
        self.assertEqual((self.root / "block.txt").read_text(), original)
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_visual_block_highlights_only_selected_tab_cells(self):
        (self.root / "tabs.txt").write_text("abcd\n\tZ\nefgh")
        e = self.start("tabs.txt")
        e.send(b"ll\x16jj")
        screen = screen_snapshot(e.output)
        self.assertEqual([reverse for _, reverse in screen[1][:5]], [False, False, True, False, False])
        e.send(b"\x1b:qa\r")
        self.assertEqual(e.wait(), 0)

    def test_visual_block_highlights_columns_and_arrows_extend_selection(self):
        (self.root / "block.txt").write_text("abcd\nefgh\nijkl")
        e = self.start("block.txt")
        e.send(b"l\x16l\x1b[B\x1b[B")
        screen = screen_snapshot(e.output)
        for row in screen[:3]:
            self.assertEqual([reverse for _, reverse in row[:4]], [False, True, True, False])
        self.assertIn(b"VISUAL BLOCK", e.output)
        e.send("d:w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "block.txt").read_text(), "ad\neh\nil")

    def test_visual_selection_highlights_and_clears_without_changing_text(self):
        (self.root / "visual.txt").write_text("abcd\nefgh\n")
        e = self.start("visual.txt")
        e.send("lvl")
        screen = screen_snapshot(e.output)
        self.assertEqual([reverse for _, reverse in screen[0][:4]], [False, True, True, False])
        self.assertIn(b"VISUAL", e.output)
        e.send(b"\x1b")
        screen = screen_snapshot(e.output)
        self.assertFalse(any(reverse for _, reverse in screen[0]))
        e.send("Vj")
        screen = screen_snapshot(e.output)
        self.assertTrue(all(reverse for _, reverse in screen[0]))
        self.assertTrue(all(reverse for _, reverse in screen[1]))
        e.send(b"\x1b:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "visual.txt").read_text(), "abcd\nefgh\n")

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

    def tools(self, **scripts):
        tools = self.root / "tools"
        tools.mkdir(exist_ok=True)
        for name, script in scripts.items():
            tool = tools / name
            tool.write_text(f"#!{sys.executable}\n" + script)
            tool.chmod(0o755)
        return {"PATH": str(tools) + os.pathsep + os.environ["PATH"]}

    def test_clipboard_binary_data_and_pipe_backpressure(self):
        payload = b"a\x00\xff\xc0" * 40000 + b"\n"
        (self.root / "source.t").write_bytes(payload)
        env = self.tools(
            pbcopy="import sys\nfrom pathlib import Path\nsys.stderr.buffer.write(b'e' * 131072)\nsys.stderr.flush()\nPath('copied.bin').write_bytes(sys.stdin.buffer.read())\n",
            pbpaste="import sys\nfrom pathlib import Path\nsys.stderr.buffer.write(b'e' * 131072)\nsys.stderr.flush()\nsys.stdout.buffer.write(Path('copied.bin').read_bytes())\n",
        )
        e = self.start("source.t", env=env)
        e.send("yy:copy\r", 0.4)
        e.expect(b"Yank register copied")
        self.assertEqual((self.root / "copied.bin").read_bytes(), payload)
        e.send(":e pasted.t\r:paste\r", 0.4)
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "pasted.t").read_bytes(), payload)

    def test_clipboard_failures_leave_editor_usable(self):
        env = self.tools(pbcopy="raise SystemExit(2)\n", pbpaste="raise SystemExit(3)\n")
        e = self.start(env=env)
        e.send(":copy\r")
        e.expect(b"pbcopy failed")
        e.send(":paste\r")
        e.expect(b"pbpaste failed")
        e.send("iok")
        e.send(b"\x1b")
        e.send(":w ok.t\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "ok.t").read_bytes(), b"ok")

    def test_search_drains_stderr_and_accepts_exit_one(self):
        (self.root / "target.t").write_text("needle\n")
        env = self.tools(rg="import sys\nsys.stderr.buffer.write(b'e' * 131072)\nsys.stderr.flush()\nsys.stdout.buffer.write(b'target.t\\0')\nraise SystemExit(1)\n")
        e = self.start(env=env)
        e.send(b"\x10", 0.5)
        deadline = time.monotonic() + 3
        while b"Literal / smart case" not in e.output and time.monotonic() < deadline:
            e.read(0.05)
        self.assertIn(b"target.t", e.output)
        self.assertIn(b"Literal / smart case", e.output)
        e.send(b"\r")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "target.t").read_text(), "Xneedle\n")

    def test_picker_cancel_terminates_child(self):
        env = self.tools(rg="import os, time\nfrom pathlib import Path\nPath('child.pid').write_text(str(os.getpid()))\ntime.sleep(30)\n")
        e = self.start(env=env)
        e.send(b"\x10", 0.2)
        pidfile = self.root / "child.pid"
        deadline = time.monotonic() + 3
        while not pidfile.exists() and time.monotonic() < deadline:
            e.read(0.03)
        child = int(pidfile.read_text())
        e.send(b"\x1b")
        with self.assertRaises(ProcessLookupError):
            os.kill(child, 0)
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_search_nonzero_failure_is_reported(self):
        env = self.tools(rg="raise SystemExit(2)\n")
        e = self.start(env=env)
        e.send(b"\x10")
        e.expect(b"rg failed")
        e.send(b"\x1b")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_save_detects_replacement_with_same_size_and_timestamp(self):
        path = self.root / "file.t"
        path.write_text("original")
        before = path.stat()
        e = self.start("file.t")
        e.send("iX")
        e.send(b"\x1b")
        replacement = self.root / "replacement.t"
        replacement.write_text("external")
        os.utime(replacement, ns=(before.st_atime_ns, before.st_mtime_ns))
        replacement.replace(path)
        e.send(":w\r")
        e.expect(b"Save refused")
        e.send(":qa!\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "external")

    def test_new_file_appearing_on_disk_is_not_overwritten(self):
        e = self.start("new.t")
        e.send("iours")
        e.send(b"\x1b")
        path = self.root / "new.t"
        path.write_text("theirs")
        e.send(":w\r")
        e.expect(b"Save refused")
        e.send(":qa!\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "theirs")

    def test_new_files_are_private_and_can_be_saved_again(self):
        e = self.start("new.t")
        e.send("ifirst")
        e.send(b"\x1b")
        e.send(":w\ra second")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        path = self.root / "new.t"
        self.assertEqual(path.stat().st_mode & 0o177, 0)
        self.assertEqual(path.read_text(), "first second")

    def test_unicode_project_root_and_filename(self):
        project = self.root / "项目"
        project.mkdir()
        path = project / "café 界.t"
        path.write_text("hello\n")
        e = self.start("--root", "项目", "café 界.t")
        e.send("iX")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "Xhello\n")

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

    def test_word_motion_and_dollar_position_inserted_text(self):
        path = self.root / "words.t"
        path.write_text("café_name...next\nlast")
        e = self.start("words.t")
        e.send("wwiX")
        e.send(b"\x1b")
        e.send("$a!")
        e.send(b"\x1b")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), "café_name...Xnext!\nlast")

    def test_open_line_and_enter_preserve_indentation_through_undo_redo(self):
        path = self.root / "indent.t"
        path.write_text(" \t  first\nnext")
        e = self.start("indent.t")
        e.send("osecond\rthird")
        e.send(b"\x1b")
        e.send("u")
        e.send(b"\x12")
        e.send(":w\r:qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual(path.read_text(), " \t  first\n \t  second\n \t  third\nnext")

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

    def test_file_picker_skips_binary_preview_but_can_open_file(self):
        payload = b"BINARY_CONTENT\n\x00data\n"
        (self.root / "binary.dat").write_bytes(payload)
        e = self.start()
        e.send(b"\x10")
        e.send("binary.dat", 0.2)
        e.expect(b"binary.dat")
        self.assertNotIn(b"BINARY_CONTENT", e.output)
        e.send(b"\r")
        e.expect(b"BINARY_CONTENT")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)
        self.assertEqual((self.root / "binary.dat").read_bytes(), payload)

    def test_file_picker_skips_non_ascii_previews(self):
        fixtures = {
            "unicode.txt": "UNICODE_CONTENT\ncafé 界 😀\n".encode(),
            "invalid.dat": b"INVALID_CONTENT\n\xff\xc0\n",
        }
        for name, payload in fixtures.items():
            (self.root / name).write_bytes(payload)
        e = self.start()
        for name, payload in fixtures.items():
            with self.subTest(name=name):
                e.send(b"\x10")
                e.send(name, 0.2)
                e.expect(b"Literal / smart case")
                self.assertNotIn(payload.split(b"\n")[0], e.output)
            e.send(b"\x1b")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_file_picker_skips_control_byte_previews(self):
        controls = (1, 8, 11, 12, 14, 27, 31, 127)
        for byte in controls:
            (self.root / f"control-{byte}.dat").write_bytes(
                f"CONTROL_CONTENT_{byte}\n".encode() + bytes([byte]) + b"\n"
            )
        e = self.start()
        for byte in controls:
            with self.subTest(byte=byte):
                e.send(b"\x10")
                e.send(f"control-{byte}.dat", 0.2)
                e.expect(b"Literal / smart case")
                self.assertNotIn(f"CONTROL_CONTENT_{byte}".encode(), e.output)
            e.send(b"\x1b")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

    def test_file_picker_previews_ascii_and_clears_it_for_binary_selection(self):
        (self.root / "ascii.txt").write_bytes(
            b"ASCII_CONTENT\n" + bytes(range(32, 127)) + b"\n\tINDENTED\r\nLAST\n"
        )
        (self.root / "binary.dat").write_bytes(b"BINARY_CONTENT\n\x00\n")
        e = self.start()
        e.send(b"\x10")
        e.send("ascii.txt", 0.2)
        e.expect(b"ASCII_CONTENT")
        e.expect(b"INDENTED")
        e.expect(b"LAST")
        e.send(b"\x7f" * len("ascii.txt") + b"binary.dat", 0.2)
        screen = screen_snapshot(e.output)
        rows = ["".join(char for char, _ in row) for row in screen]
        self.assertIn("binary.dat", rows[3])
        for row in rows[3:23]:
            self.assertEqual(row[51:98].strip(), "")
        self.assertNotIn(b"BINARY_CONTENT", e.output)
        e.send(b"\x7f" * len("binary.dat") + b"ascii.txt", 0.2)
        screen = screen_snapshot(e.output)
        self.assertIn("ASCII_CONTENT", "".join(char for char, _ in screen[3]))
        e.send(b"\x1b")
        e.send(":qa\r")
        self.assertEqual(e.wait(), 0)

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
