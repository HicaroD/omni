# Omni

A Vim-inspired terminal editor written in [Telia](https://github.com/HicaroD/Telia).
Currently supports macOS. An early implementation, not a Neovim replacement.

## Features

- Normal and Insert modes, undo/redo, and search.
- Multiple buffers and nested horizontal/vertical splits.
- Fuzzy file and buffer pickers with previews.
- Project search powered by [ripgrep](https://github.com/BurntSushi/ripgrep).
- Rope-based text storage and incremental terminal rendering.

## Build and run

Requires **[Telia v0.3.0](https://github.com/HicaroD/Telia)**, Xcode command-line tools, and `rg` on your `PATH`.
Use an ANSI-compatible terminal with a UTF-8 locale.

```sh
make build
./bin/omni
./bin/omni main.t README.md
./bin/omni --root /path/to/project main.t
```

The launch directory is the project root unless you pass `--root`.

## Quick reference

| Keys | Action |
| --- | --- |
| `h j k l`, arrows | Move |
| `i`, `a`, `o` | Enter Insert mode |
| `Esc` | Return to Normal mode / cancel |
| `x`, `dd`, `yy`, `p` | Delete character, delete line, yank line, paste |
| `u`, `Ctrl-r` | Undo / redo |
| `/`, `n`, `N` | Search, next match, previous match |
| `Ctrl-p`, `Ctrl-f`, `Ctrl-b` | Find files, search project, switch buffers |
| `:e path`, `:w`, `:w path` | Open, save, save as |
| `:q`, `:wq`, `:qa` | Close, save and close, quit all |
| `:split`, `:vsplit` | Split horizontally / vertically |
| `Ctrl-w` then `h j k l` | Focus another split |

Unsaved changes block normal exit. Use `:qa!` to quit without saving.
Project search reads files on disk, not unsaved buffers. Syntax highlighting,
LSP, plugins, and full Vim compatibility are not implemented.

See the [guide](docs/guide.md) for all commands, picker controls, clipboard use,
file-safety details, architecture, and known limits.

## Tests

Requires Python 3 for terminal integration tests.

```sh
make unit          # Native Telia tests
make test          # Unit and terminal integration tests
make test-release  # Test the optimized editor
make sanitize      # UndefinedBehaviorSanitizer
```
