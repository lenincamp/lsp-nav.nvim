-- lsp-nav.nvim: Native LSP navigation UI (peek, symbols, call hierarchy).
-- Zero dependencies — uses only Neovim built-in LSP and treesitter APIs.

local M = {}

function M.setup(opts)
  -- Reserved for future config (keymaps prefix, etc.)
  M._opts = opts or {}
end

-- ── Peek ──────────────────────────────────────────────────────────────

function M.peek(method)
  require("lsp-nav.peek").request(method)
end

function M.peek_definition()
  M.peek("textDocument/definition")
end

function M.peek_type_definition()
  M.peek("textDocument/typeDefinition")
end

function M.peek_declaration()
  M.peek("textDocument/declaration")
end

function M.peek_implementation()
  M.peek("textDocument/implementation")
end

function M.peek_close_all()
  require("lsp-nav.peek").close_all()
end

function M.peek_location(location)
  return require("lsp-nav.peek").preview_location(location)
end

function M.register_pre_handler(method, handler)
  require("lsp-nav.peek").register_pre_handler(method, handler)
end

-- ── LSP Lists ─────────────────────────────────────────────────────────

function M.references()
  require("lsp-nav.lists").references()
end

function M.document_symbols()
  require("lsp-nav.lists").document_symbols()
end

function M.workspace_symbols()
  require("lsp-nav.lists").workspace_symbols()
end

-- ── Call Hierarchy ────────────────────────────────────────────────────

function M.call_hierarchy(direction)
  require("lsp-nav.hierarchy").open(direction)
end

function M.call_hierarchy_incoming()
  require("lsp-nav.hierarchy").incoming()
end

function M.call_hierarchy_outgoing()
  require("lsp-nav.hierarchy").outgoing()
end

return M
