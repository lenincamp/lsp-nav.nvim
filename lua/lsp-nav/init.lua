-- lsp-nav.nvim: Native LSP navigation UI (peek, symbols, call hierarchy).
-- Zero dependencies — uses only Neovim built-in LSP and treesitter APIs.

local M = {}

-- Default keymaps: { [lhs] = { mode, action, desc } }
-- User can remap via setup({ keymaps = { grr = "<leader>lr", ... } })
local DEFAULT_KEYMAPS = {
  -- Peek
  gpc  = { "n", function() M.peek_close_all() end,              "Peek: close all" },
  gpd  = { "n", function() M.peek_definition() end,             "Peek Definition" },
  gpt  = { "n", function() M.peek_type_definition() end,        "Peek Type Definition" },
  gpi  = { "n", function() M.peek_implementation() end,         "Peek Implementation" },
  gpD  = { "n", function() M.peek_declaration() end,            "Peek Declaration" },
  gpr  = { "n", function() M.references() end,                  "Peek References (picker)" },
  -- Call Hierarchy
  ["<leader>ch"] = { "n", function() M.call_hierarchy("incoming") end, "Call Hierarchy" },
  ["<leader>ci"] = { "n", function() M.call_hierarchy_incoming() end,  "Incoming Calls" },
  ["<leader>co"] = { "n", function() M.call_hierarchy_outgoing() end,  "Outgoing Calls" },
  -- LSP Lists
  grr  = { "n", function() M.references() end,       "References" },
  gO   = { "n", function() M.document_symbols() end,  "Document Symbols" },
  gW   = { "n", function() M.workspace_symbols() end, "Workspace Symbols" },
  ["<leader>ss"] = { "n", function() M.document_symbols() end,  "LSP Symbols (doc)" },
  ["<leader>sS"] = { "n", function() M.workspace_symbols() end, "LSP Symbols (workspace)" },
}

local function apply_keymaps(overrides, buf)
  local map_opts = function(desc) return { buffer = buf, desc = desc, silent = true } end

  for lhs, def in pairs(DEFAULT_KEYMAPS) do
    local override = overrides and overrides[lhs]
    if type(override) == "string" then
      vim.keymap.set(def[1], override, def[2], map_opts(def[3]))
    else
      vim.keymap.set(def[1], lhs, def[2], map_opts(def[3]))
    end
  end
end

function M.setup(opts)
  opts = opts or {}
  M._opts = opts

  -- Wire picker.nvim when available so document/workspace symbols use the full UI.
  local ok, picker = pcall(require, "picker")
  if ok and picker.select_items then
    require("lsp-nav.lists").set_picker(picker.select_items)
  end

  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("lsp-nav-keymaps", { clear = true }),
    callback = function(ev)
      -- Defer to run after Neovim's built-in LspAttach keymaps (grr, gO, etc.)
      vim.schedule(function()
        apply_keymaps(type(opts.keymaps) == "table" and opts.keymaps or nil, ev.buf)
      end)
    end,
  })
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
