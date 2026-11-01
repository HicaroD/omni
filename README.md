# Omni

A Vim-inspired terminal editor written in [Telia](https://github.com/HicaroD/Telia).
Currently supports macOS. An early implementation, not a Neovim replacement.

## Features

- Normal and Insert modes, undo/redo, and search.
- Multiple buffers and nested horizontal/vertical splits.
- Fuzzy file and buffer pickers with previews.
- Project search powered by [ripgrep](https://github.com/BurntSushi/ripgrep).
- Rope-based text storage and incremental terminal rendering.

## Install

Prebuilt releases support **Apple Silicon Macs running macOS 14 or later**.
No Telia compiler, Xcode, or administrator privileges are needed.

```sh
curl -fsSL https://raw.githubusercontent.com/HicaroD/omni/master/install.sh | sh
```

The installer verifies the release's SHA-256 checksum and installs `omni` into
`~/.local/bin`. Add that directory to your `PATH` if prompted. It never edits
shell configuration. Run the command again to upgrade.

The command requires a public repository and at least one published release;
it is not available anonymously while this repository is private.

Project search additionally needs `rg`: `brew install ripgrep`.
Use an ANSI-compatible terminal with a UTF-8 locale.

To inspect the script first, pin a version, or choose another install directory:

```sh
curl -fsSLo install-omni.sh https://raw.githubusercontent.com/HicaroD/omni/master/install.sh
less install-omni.sh
OMNI_VERSION=v0.1.0 OMNI_BIN_DIR="$HOME/tools/bin" sh install-omni.sh
```

`OMNI_BIN_DIR` must be an absolute path. An Intel Mac or a terminal running under
Rosetta is not supported. Uninstall with `rm "$HOME/.local/bin/omni"` (adjust
the path if you used a custom directory).

See [release instructions](docs/releases.md) for publishing binaries.

## Build and run

Requires **[Telia v0.3.2](https://github.com/HicaroD/Telia)**, Xcode command-line tools, and `rg` on your `PATH`.
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
| `w`, `$` | Next word, line end |
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
