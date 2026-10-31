# Omni

A keyboard-driven terminal editor written in **Telia v0.2.1**. Vim-inspired,
not Vim-compatible. Currently targets macOS.

## Build and run

Requires Telia v0.2.1, Xcode command-line tools, and [ripgrep](https://github.com/BurntSushi/ripgrep)
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

`make` sets `T_VENDOR_PATH` to this repository's `vendor` directory. No Telia
compiler or standard-library modifications are required.

## Editing

| Keys | Action |
| --- | --- |
| `h j k l`, arrows | Move left/down/up/right |
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
  permission bits. Failed writes do not truncate the original file.
- Saves refuse a destination that already exists under another name, a file
  already open in another buffer, or a detected external modification. There is
  no force-overwrite command yet; save to another path to recover your edits.
- Canonical paths deduplicate `file.t`, `./file.t`, and symlink aliases. Editing
  through a symlink saves its resolved target without replacing the link.
- Modification detection uses filesystem metadata, not a lock or content hash.
  It does not eliminate concurrent-write races. Atomic replacement changes inode
  identity, does not preserve hard links, ACLs, or extended attributes, and does
  not guarantee directory-entry durability across power loss.
- File bytes, including invalid UTF-8 and NUL, are preserved on load/save.
  Undisplayable/control bytes render as `?`, never as terminal commands.
- Navigation/deletion is code-point-oriented for valid UTF-8, not grapheme-aware.
  Display widths use macOS `wcwidth`; tabs use four-column stops. Combining and
  wide characters are supported, but complex emoji and terminal-specific width
  differences can still misalign. Newlines are LF; existing CR bytes are retained.

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
vendor/platform/          narrow macOS file/process/width/argv ABI adapter
tests/                    Telia rope tests and real-PTY integration tests
```

Rope nodes hold up to 512 bytes with cached subtree byte/newline counts. Random
priorities provide **expected**, not worst-case, logarithmic navigation and edits.
Nearby typing fills existing chunks; deletions release removed nodes. Chunk
boundaries can fall inside a UTF-8 sequence; decoding reads across them. All
fallible allocations for a splice occur before the tree is mutated. Undo records
own deleted/inserted bytes; snapshots are not persistent ropes.

Terminal state is restored through normal error returns and deferred cleanup;
`@fail` is confined to the outer entry point. Forced process termination or a
runtime panic cannot guarantee restoration. Use `reset` if the terminal is left
in a bad state after a crash.

### Telia v0.2.1 compatibility notes

- There is no `break`/`continue` support; loops use conditions and state flags.
- Indexed expressions emit bounds-check setup before their surrounding
  expression. Avoid indexed reads in short-circuit guards and loop conditions;
  `byte_at` keeps the check inside a function evaluated at the intended time.
- Build the project directory by absolute path, as the Makefile does. Building
  `.` directly currently produces an invalid output path with this compiler.
- The session uses standard terminal handles. On this macOS host, polling a
  separately opened `/dev/tty` reports `POLLNVAL`.

### Current limits

This is an initial implementation, not a production replacement for Neovim.

- No highlighting, LSP, plugins, mouse, Visual modes, composed motions, counts,
  macros, autoindent, soft wrapping, or persistent configuration.
- Pickers retain up to 50,000 candidates and show the top 100. Previews read at
  most the first MiB. Individual search records larger than a MiB stop the scan.
- File loading/saving, preview loading, in-buffer search, and clipboard commands
  are synchronous. Large documents and long lines still need performance work.
- Changed rows are repainted as units rather than diffing individual cells;
  frame composition still visits the viewport. Filename fuzzy matching is
  byte-based and folds ASCII case only.
- Undo history is unbounded until a buffer is closed. There is no crash recovery,
  swap file, background autosave, external reload command, or signal cleanup hook.
- Only macOS is configured; local verification is on Apple Silicon. Intel macOS
  has a native manifest entry but has not been tested here.

Rendering caches rows and writes only rows whose content changed; ordinary
updates never clear the screen. Picker overlays mask covered document content
instead of repainting it underneath the picker. Cursor visibility changes only
when opening/closing an overlay or when a view cannot display the cursor.
Synchronized updates are enabled automatically for Kitty, Ghostty, and WezTerm
outside tmux. Set `OMNI_SYNC_UPDATES=1` to enable them explicitly or `0` to disable
them. Other terminals use ordinary batched updates without relying on this
extension.

## Verification

```sh
make test                   # debug build, randomized rope checks, 26 PTY tests
make test-release           # repeat with optimized builds
make sanitize               # UndefinedBehaviorSanitizer, including generated C
OMNI_SANITIZERS=address,undefined make sanitize
cc -Wall -Wextra -Werror -fsyntax-only vendor/platform/platform.c
```

The rope suite checks 1,800 deterministic randomized splices against a flat byte
buffer, including NUL/invalid UTF-8, cached counts, line lookup, heap ordering,
tree height, copying, invalid ranges, and full deletion. PTY tests exercise
editing, undo, splits, pickers/search, paste fragmentation, resizing, save guards,
symlinks, and terminal restoration without touching the developer's terminal.

Sanitizer runs first probe the host runtime. AddressSanitizer hangs even for a
minimal C program on the initial development host; it has **not** been validated
there. Debug, release, UBSan, and native warning checks pass.

Telia references: [repository](https://github.com/HicaroD/Telia),
[terminal](https://github.com/HicaroD/Telia/blob/50a3c9a235bb62190718dbfb75cffeea3fd30731/docs/terminal.md),
[collections](https://github.com/HicaroD/Telia/blob/50a3c9a235bb62190718dbfb75cffeea3fd30731/docs/collections.md).
