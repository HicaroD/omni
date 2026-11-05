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

Configuration loads from `~/.config/omni/config.toml` (or `XDG_CONFIG_HOME`).
Use `--config path` or `--no-config` to override discovery. See the
[configuration guide](configuration.md) for mode-specific mappings, the comma
leader, timeout behavior, and the deliberately small TOML subset.

## Editing

| Keys | Action |
| --- | --- |
| `h j k l`, arrows | Move left/down/up/right |
| `w` | Move to the start of the next word |
| `f{char}`, `F{char}`, `t{char}`, `T{char}` | Find forward/backward; stop before/after a character |
| `;`, `,` | Repeat the last character find; repeat in the opposite direction |
| `0`, `$`, `gg`, `G` | Line start/end, first/last line |
| `i`, `a`, `o` | Insert before cursor, append, open a line below |
| `I`, `A`, `O` | Insert at first nonblank, append at line end, open a line above |
| `s`, `C` | Substitute character(s), change from cursor to line end |
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

`o`, `O`, and Insert-mode Enter copy the line's leading spaces and tabs onto the new
line, placing the cursor after the indentation. Enter within indentation copies
only the prefix before the cursor. No language-specific indentation is added.

`I` skips leading spaces and tabs; on a whitespace-only line it inserts after
that indentation. `A` appends before the newline, or at EOF. `O` opens above
the current line, including the first line. Opening a line and typing into it
undo together.

`3s` substitutes up to three UTF-8 code points on the current line without
removing its newline. `C` is shorthand for `c$`; `2C` changes through the end of
the following line. Deleted text is available to `p`. On an empty line, `s` and
`C` enter Insert mode without clearing the previous yank. Deletion and replacement
text undo together.

`w` distinguishes keyword runs (letters, digits, underscores, and non-ASCII
characters) from punctuation runs. It skips whitespace across lines, stops on
empty lines, and stays on a UTF-8 character boundary at the end of the buffer.

Search wraps and uses ASCII smart case: queries with uppercase ASCII letters
match case-sensitively. No regex support for in-buffer search yet.

### Counts and composed edits

Normal-mode motions accept counts: `3w`, `2b`, `10l`, `2j`. `0` still moves to
line start; zero after another digit extends the count. `3G` and `3gg` go to
line three, while `2$` goes to the end of the following line.

Combine `d` (delete), `c` (change), or `y` (yank) with `h`, `l`, `w`, `b`, `0`,
`$`, `j`, `k`, or a character find. Vertical operators act on complete lines. Repeat an operator
for whole lines: `dd`, `cc`, `yy`. Counts before and after an operator multiply:
`2d3w` deletes six words. `cw` preserves whitespace after the changed word.

Word text objects work with these operators: `ciw` changes the whole word under
the cursor, `diw` deletes its contents, and `daw` also removes adjacent spaces.
Keyword and punctuation runs are separate words. Counted `iw` treats whitespace
as a separate object, matching Vim; `aw` counts words with their adjacent spaces.
Changes and their replacement text undo together. Esc or Ctrl-c cancels a pending
operator/count; invalid operator sequences are discarded without editing.

Counts currently apply to these Normal-mode motions, operators, and word objects,
plus `s` and `C`, not all commands or Visual mode. Insert repetition such as
`3Itext` or `3Otext` is not implemented. Other text objects and `.` repeat are not yet
implemented.

### Character finds

`f)` moves onto the next `)` on the current line; `F(` searches backward.
`t)` stops just before a forward target, while `T(` stops just after a backward
target. Counts select an occurrence: `2f)` finds the second following `)`.
Targets may be UTF-8 code points, tabs, or spaces. Searches never cross a newline;
if the requested occurrence does not exist, the cursor and text stay unchanged.

`;` repeats the last find with a fresh count (`2;`), and `,` reverses its direction
without changing the remembered direction. Repeating `t`/`T` skips an adjacent
target that would leave the cursor unchanged. Finds also extend Visual selections,
including block selections; Visual-mode counts are still unsupported.

Operators compose with finds and repeats: `df)` deletes through `)`, `dt)` leaves
the target intact, `ct"` changes up to a quote, and `y2f,` yanks through the second
comma. Counts multiply as usual. Backward operators leave the original cursor's
character intact. A failed find does not perform a partial edit or erase the yank.
Esc, Ctrl-c, Backspace, arrows, and invalid target encodings cancel an unfinished
find. The last find is shared across buffers for the current editor session.

### Visual selection

Start a selection in Normal mode, move its endpoint, then apply an operator.
The status shows `VISUAL`, `VISUAL LINE`, or `VISUAL BLOCK`.

| Keys | Action |
| --- | --- |
| `v`, `V`, `Ctrl-v` | Characterwise, whole-line, or rectangular selection |
| Movement keys, arrows, `0`, `$`, `gg`, `G`, `/`, `n`, `N` | Extend the selection |
| `o` | Swap the active endpoint and anchor |
| Block `O` | Switch horizontal corners on the same row |
| `d`, `x` | Delete selection into the local yank register |
| `y` | Yank selection without changing text |
| `c` | Delete selection and enter Insert mode |
| `p`, `P` | Replace selection; `P` preserves the existing yank register |
| Block `I`, `A` | Insert before / append after the rectangle |
| `Esc`, `Ctrl-c`, or the current selection key | Cancel selection |

Press another selection key to change its type without resetting the anchor.
Character selections include both endpoints. For example, `Vjjd` deletes three
lines and `Vjjy` copies three lines. After an operator, selection ends; `p` in
Normal mode pastes using the register's character, line, or block shape.
Use `:copy` after yanking to copy the register to the macOS clipboard.

Rectangles use display columns, including four-column tabs and wide characters.
A tab at an endpoint is included in full; partially selected interior tabs are
split into spaces when necessary. Short rows do not have text deleted beyond
their ends. Block paste pads short destination rows and can create new lines.
Block `$` follows every selected row's end; `$A` appends at each row's own end.

For block `c`, `I`, and `A`, type on the first row and press **Esc** to repeat the
inserted text on the other rows. `I` and `c` skip rows shorter than the left edge;
`A` pads them. Arrows, Ctrl-c, or backspacing before the insertion point cancel
repetition, leaving the first-row edits intact. Multi-line block insertion is
not supported. A completed Visual edit, including block repetition, undoes as
one operation. Press Esc before switching buffers/windows or entering commands.

This is a Vim-style subset: `gv`, Visual text objects, named registers, Visual counts, Visual
indentation/case operators, and Visual Ex ranges are not implemented.

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
editor/constants.t        typed modes/registers/pickers and named key/text bytes
editor/commands.t         modal commands, navigation, search, clipboard
editor/operators.t        composed operators and shared edit-range application
editor/objects.t          word text-object ranges
editor/insert.t           insert entry points, indentation, open-above and substitute
editor/find.t             character-find input, motions, repeats and operator ranges
editor/visual.t           selection ranges, rectangular edits and block insertion
editor/input.t            streaming key/escape/paste decoder
editor/render.t           terminal-cell layout and batched rendering
editor/screen.t           row cache, changed-row writes, cursor/sync state
editor/picker.t           fuzzy ranking, incremental rg results, previews
editor/session.t          terminal lifecycle, CLI, event loop
editor/config.t           configuration schema, discovery and validation
editor/mapping.t          key notation, mapping prefixes and fallback
editor/actions.t          named mapping actions
editor/clock.t            macOS monotonic mapping deadlines
toml/toml.t               small native TOML configuration parser
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

- No syntax highlighting, LSP, plugins, mouse, full Vim motion/operator compatibility,
  macros, language-aware indentation, soft wrapping, or per-language configuration.
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
