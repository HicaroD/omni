# Omni guide

A keyboard-driven terminal editor written in **[Telia v0.3.2](https://github.com/HicaroD/Telia)**. Vim-inspired,
not Vim-compatible. Currently targets macOS.

## Build and run

Requires [Telia v0.3.2](https://github.com/HicaroD/Telia), Xcode command-line tools, and [ripgrep](https://github.com/BurntSushi/ripgrep)
(`rg` on `PATH`). Python 3 is needed only for the test suite.

```sh
telia version
make build
./bin/omni                         # unnamed buffer
./bin/omni main.t README.md        # open several files
./bin/omni --root /path/to/project main.t
```

Run inside an ANSI-compatible terminal with UTF-8 locale settings. Both standard
input and output must be terminals. The launch directory is the project root;
`--root` changes it before opening files. Relative file paths use that root.

## Editing

| Keys | Action |
| --- | --- |
| `h j k l`, arrows | Move left/down/up/right |
| `w` | Move to the start of the next word |
| `0`, `$`, `gg`, `G` | Line start/end, first/last line |
| `i`, `a`, `o` | Insert before cursor, append, open a line below |
| `Esc`, `Ctrl-c` | Return to Normal mode / cancel prompt or picker |
| `x`, `dd` | Delete character / line into the editor-local yank register |
| `yy`, `p` | Yank line / paste after character or line |
| `u`, `Ctrl-r` | Undo / redo |
| `/`, `n`, `N` | Literal in-buffer search, next/previous match |
| `Ctrl-p`, `Ctrl-f`, `Ctrl-b` | File, project-search, buffer picker |
| `Ctrl-^` | Previous buffer |

Insert mode accepts text, Enter, Tab, Backspace, and arrows. Bracketed paste is
inserted literally as one undo unit, including newlines and command-like text.
It is ignored outside Insert mode. An Insert session is grouped for undo.

`o` and Insert-mode Enter copy the line's leading spaces and tabs onto the new
line, placing the cursor after the indentation. Enter within indentation copies
only the prefix before the cursor. No language-specific indentation is added.

`w` distinguishes keyword runs (letters, digits, underscores, and non-ASCII
characters) from punctuation runs. It skips whitespace across lines, stops on
empty lines, and stays on a UTF-8 character boundary at the end of the buffer.

Search wraps and uses ASCII smart case: queries with uppercase ASCII letters
match case-sensitively. No regex support for in-buffer search yet.

### Commands

Enter `:` in Normal mode; press Enter to execute or Esc to cancel. The remainder
after the first space is the path, so paths containing spaces do not need quotes.

| Command | Action |
| --- | --- |
| `:e path` | Open/create a file; retain other buffers, including unsaved ones |
| `:w`, `:w path` | Save / save under a new path |
| `:q`, `:q!`, `:wq` | Close split or exit; force close; save then close |
| `:qa`, `:qa!` | Exit all; force exit and discard unsaved changes |
| `:bn`, `:bp`, `:b#` | Next, previous, previously active buffer |
| `:buffers` (`:ls`), `:bd` | Buffer picker; close current saved buffer |
| `:split [path]`, `:vsplit [path]` | Horizontal/vertical split |
| `:files`, `:grep [query]` | File finder / project-text search |
| `:copy` | Copy the local yank register to macOS using `pbcopy` |
| `:paste` | Insert macOS clipboard contents at cursor using `pbpaste` |
| `:help` | Short command reminder |

Closing is conservative: unsaved buffers prevent normal exit. `:bd` cannot close
the last buffer. The initial unnamed buffer remains available when opening files.

### Splits

Press `Ctrl-w`, then:

| Key | Action |
| --- | --- |
| `s`, `v` | Horizontal / vertical split |
| `h j k l` | Focus in that direction |
| `c`, `=` | Close active split / equalize split ratios |
| `+`, `-` | Increase / decrease active split height |
| `>`, `<` | Increase / decrease active split width |

Splits can nest and display the same buffer. Cursors are adjusted when shared
text changes. Each view remembers cursor/scroll positions when switching buffers.
Very small panes cannot be split further.

### Pickers

Type to filter filenames or buffer names using subsequence fuzzy matching. Project
search runs `rg` asynchronously, restarting and cancelling the previous process
when the query changes. Results open at the reported line/byte column.

- `Ctrl-j` / `Ctrl-k` or arrows: select a result.
- Enter: open; Esc: cancel.
- `Ctrl-h`: include/exclude hidden files.
- Tab: include/exclude ignored files.
- `Ctrl-r`: toggle regex for project search (literal by default).
- The right side previews the selected file or live buffer.

File discovery and search respect ripgrep's ignore rules by default. `.git`
directories remain excluded even with hidden/ignored files enabled. Search reads
**files on disk**, not unsaved buffers. Buffer previews use live text.

## File safety and text handling

- Saves use a same-directory temporary file, `fsync`, and rename, preserving Unix
  permissions. New files are private (at most `0600`, subject to umask).
  Pre-replacement failures preserve the original. "Written; directory
  synchronization failed" means the save completed, but durability is uncertain.
- Saves refuse a destination that already exists under another name, a file
  already open in another buffer, or a detected external modification. There is
  no force-overwrite command yet; save to another path to recover your edits.
- Canonical paths deduplicate `file.t`, `./file.t`, and symlink aliases. Editing
  through a symlink saves its resolved target without replacing the link.
- Metadata checks do not prevent concurrent-write races. Replacement changes file
  identity, does not preserve hard links, ACLs, or extended attributes, and cannot
  guarantee durability across power loss.
- File bytes, including invalid UTF-8 and NUL, are preserved on load/save.
  Undisplayable/control bytes render as `?`, never as terminal commands.
- Paths, arguments, and environment values must be valid UTF-8. Loads/previews
  reject nonregular files, but concurrent path replacement can race that check.
- Navigation/deletion is code-point-oriented for valid UTF-8, not grapheme-aware.
  Display uses Unicode 17 widths and four-column tabs. Complex emoji and terminal
  width differences can misalign. Newlines are LF; existing CR bytes are retained.

## Architecture

```text
main.t                    entry point; fatal errors only after session cleanup
rope/rope.t               mutable chunked rope (randomized implicit treap)
editor/model.t            buffers, edit history, views, split ownership
editor/commands.t         modal commands, navigation, search, clipboard
editor/input.t            streaming key/escape/paste decoder
editor/render.t           terminal-cell layout and batched rendering
editor/screen.t           row cache, changed-row writes, cursor/sync state
editor/picker.t           fuzzy ranking, incremental rg results, previews
editor/session.t          terminal lifecycle, CLI, event loop
editor/process.t          search and clipboard subprocesses
*_test.t                  native Telia rope/editor unit tests
tests/                    real-PTY integration tests and sanitizer tooling
```

The rope uses 512-byte chunks with cached byte/newline counts and expected
logarithmic navigation/edits. Undo records own changed bytes. Rendering caches
rows and repaints only changed rows.

Normal shutdown restores terminal state; crashes or forced termination may not.
Run `reset` if the terminal is left in a bad state.

## Limits

- No highlighting, LSP, plugins, mouse, Visual modes, composed motions, counts,
  macros, language-aware indentation, soft wrapping, or persistent configuration.
- Pickers retain up to 50,000 candidates and show the top 100. Previews read at
  most the first MiB. Individual search records larger than a MiB stop the scan.
- File loading/saving, preview loading, in-buffer search, and clipboard commands
  are synchronous. Large documents and long lines still need performance work.
- Filename fuzzy matching is byte-based and folds ASCII case only.
- Undo history is unbounded until a buffer is closed. There is no crash recovery,
  swap file, background autosave, external reload command, or signal cleanup hook.
- Only macOS is supported; local verification is on Apple Silicon. Intel macOS
  and other platforms have not been tested here.

Synchronized updates are automatic in Kitty, Ghostty, and WezTerm outside tmux.
Override with `OMNI_SYNC_UPDATES=1` (on) or `0` (off).

## Verification

```sh
make unit                   # Unit tests
make test                   # Unit and isolated terminal integration tests
make test-release           # Test the optimized editor
make test-install           # Installer checks
make sanitize               # UndefinedBehaviorSanitizer
OMNI_SANITIZERS=address,undefined make sanitize
```

Tests cover randomized rope edits, input, rendering, save guards, search, clipboard,
and terminal cleanup. Release tests optimize the editor, not the unit-test runner.
Sanitizer runs probe the host runtime first; ASan remains unverified on the local
macOS host because its runtime hangs.
