# lsp-nav.nvim

Native LSP navigation UI for Neovim — peek definitions, browse call hierarchy, and list symbols/references.

Zero external dependencies. Uses only built-in Neovim LSP and treesitter APIs.

## Features

- **Peek** — Chainable floating preview windows with treesitter-aware function body detection. Supports stack navigation (peek inside peek), JDTLS `jdt://` URIs, and editable buffers.
- **Call Hierarchy** — Interactive tree browser for incoming/outgoing calls with lazy expansion.
- **LSP Lists** — References, document symbols, and workspace symbols with quickfix/picker integration.

## Requirements

- Neovim ≥ 0.10
- At least one LSP client attached

## Installation

```lua
-- lazy.nvim
{ "lcampoverde/lsp-nav.nvim", opts = {} }

-- Or manual: clone to pack path
-- ~/.local/share/nvim/site/pack/plugins/opt/lsp-nav.nvim
```

## Setup

```lua
require("lsp-nav").setup({})
```

### Custom picker (optional)

By default, document symbols and references open in the quickfix list. To use a custom picker (e.g., Telescope, fzf-lua, or your own):

```lua
require("lsp-nav.lists").set_picker(function(items, opts, on_select)
  -- your picker here; call on_select(chosen_item) when done
end)
```

## API

### Peek

| Function | Description |
|----------|-------------|
| `require("lsp-nav").peek(method)` | Peek any LSP method |
| `require("lsp-nav").peek_definition()` | Peek definition |
| `require("lsp-nav").peek_type_definition()` | Peek type definition |
| `require("lsp-nav").peek_declaration()` | Peek declaration |
| `require("lsp-nav").peek_implementation()` | Peek implementation |
| `require("lsp-nav").peek_close_all()` | Close entire peek stack |
| `require("lsp-nav").peek_location(loc)` | Preview arbitrary location `{filename, lnum, col}` |
| `require("lsp-nav").register_pre_handler(method, fn)` | Intercept peek request (return `true` to skip LSP) |

**Peek keymaps** (inside floating window):
- `<CR>` — Jump to file
- `<BS>` — Back one level
- `q` / `<Esc>` — Close current peek
- `<C-Up>` / `<C-Down>` — Resize

### Call Hierarchy

| Function | Description |
|----------|-------------|
| `require("lsp-nav").call_hierarchy("incoming")` | Open incoming calls |
| `require("lsp-nav").call_hierarchy("outgoing")` | Open outgoing calls |
| `require("lsp-nav").call_hierarchy_incoming()` | Shortcut for incoming |
| `require("lsp-nav").call_hierarchy_outgoing()` | Shortcut for outgoing |

**Hierarchy keymaps** (inside hierarchy buffer):
- `<CR>` — Jump to symbol
- `o` / `<Tab>` / `za` — Toggle/expand node
- `i` — Switch to incoming
- `O` — Switch to outgoing
- `r` — Refresh tree
- `Q` — Send to quickfix
- `q` — Close
- `?` — Toggle help

### LSP Lists

| Function | Description |
|----------|-------------|
| `require("lsp-nav").references()` | List references |
| `require("lsp-nav").document_symbols()` | List document symbols |
| `require("lsp-nav").workspace_symbols()` | Interactive workspace symbol search |

## License

MIT
