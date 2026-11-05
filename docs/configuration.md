# Configuration and key mappings

Omni reads configuration once at startup, from:

1. `--config path`, if supplied (the file must exist).
2. `$XDG_CONFIG_HOME/omni/config.toml`, when `XDG_CONFIG_HOME` is absolute.
3. `$HOME/.config/omni/config.toml` otherwise.

A missing default file uses built-in defaults. `--no-config` bypasses discovery;
it cannot be combined with `--config`. Relative explicit paths use the project
root, including `--root`. Omni does not create or modify configuration files,
load project-local configuration, or execute shell commands from configuration.

Invalid configuration stops startup **before terminal modes change**, with the
file and line reported. Unknown settings/actions, wrong types, and duplicate
bindings after leader/key-token expansion are errors. Config files must be
regular files of at most 128 KiB.

## Example

```toml
[keys]
leader = ","       # Default; use '<Space>' for a Space leader
timeout_ms = 1000   # Default; allowed range: 1–60000

[keys.normal]
"<leader>w" = "action:write"
"<leader>ff" = "action:files"
"<leader>fg" = "action:search"
"<leader>fb" = "action:buffers"
"<leader>u" = "action:undo"
"<leader>r" = "action:redo"
H = "0"
L = "$"

[keys.insert]
jk = "<Esc>"

[keys.visual]
q = "d"
```

Mappings may invoke an `action:name` or play a sequence of built-in keys.
Replacements are **nonrecursive**: if `x = "l"` and `l = "x"`, pressing `x`
moves right rather than deleting text. An empty replacement disables that binding.
The Visual table applies to character, line, and block selections.

### Key notation

Use ordinary characters, including literal UTF-8, or these case-sensitive tokens:

| Token | Key |
| --- | --- |
| `<leader>` | Configured leader sequence; expanded when loading config |
| `<Space>`, `<Tab>` | Space, Tab |
| `<CR>`, `<Enter>` | Enter |
| `<BS>` | Backspace |
| `<Esc>` | Escape, in replacement sequences only |
| `<C-a>` … `<C-z>` | Ctrl-letter |
| `<lt>` | Literal `<` |

`Esc` and `Ctrl-c` are reserved cancellation keys and cannot appear in a
mapping's input sequence. The leader uses the same notation except `<leader>`
itself. Expanded input/replacement sequences are limited to 256 bytes.

### Actions

Available actions are `write`, `files`, `search`, `buffers`, `undo`, `redo`,
`quit`, `split`, `vsplit`, and `normal`. Use the `action:` prefix, for example
`"<leader>w" = "action:write"`. `quit` respects unsaved-file guards; `normal`
acts like Escape. Other actions use the editor's existing behavior.

### Prefixes and timeout

A key only waits if it is a prefix of a configured mapping. Pending keys appear
on the message row as `Keys: …`. Each additional key restarts `timeout_ms`.

If both `g` and `gg` are mapped, Omni waits after `g`. Timeout executes the shorter
mapping. On a mismatch, the longest completed mapping executes and remaining
input is processed normally. Without a completed mapping, buffered input falls
back to built-in keys; typed Insert-mode text is not dropped.

Comma is still reverse-character-find. With no comma-prefixed mapping, it acts
immediately. If comma starts a leader mapping, a lone comma performs its built-in
action after timeout. Change the leader to avoid that delay.

Escape cancels a Normal/Visual prefix without executing it. In Insert mode,
pending literal text is inserted before leaving the mode. Arrows flush pending
text before moving. Bracketed paste bypasses mappings and remains literal.

### Current boundaries

Mappings apply at Normal/Visual command boundaries and during ordinary Insert
input. They do not intercept operator-pending input, keys after a count has begun, character-find
targets, command/search prompts, pickers, or replicated Visual-block insertion.
Arrow/function-key mapping tokens, recursive mappings, config reload, per-language
settings, themes, and extension settings are not implemented yet.

## Small TOML subset

The native Telia parser in `toml/toml.t` intentionally supports only:

- Bare keys (`letters`, digits, `_`, `-`) and single-line quoted keys.
- Bare dotted table names such as `[keys.normal]`, without interior whitespace.
- Single-line basic (`"…"`) and literal (`'…'`) strings. Basic escapes are
  `\b`, `\t`, `\n`, `\f`, `\r`, `\"`, and `\\`; literal strings do not unescape.
- Nonnegative signed-64-bit-range decimal integers, optional `+`, and underscores
  between digits; lowercase `true`/`false` booleans.
- Blank lines, `#` comments, UTF-8 text, LF and CRLF line endings.

Arrays, inline tables, table arrays, quoted table names, dotted assignments,
multiline strings, Unicode escape notation, negative/base-prefixed numbers,
floats, and dates are unsupported and produce errors. Write Unicode characters
directly. Only the settings shown above are accepted by the editor schema;
booleans are parsed for future settings but are not used by the current schema.
