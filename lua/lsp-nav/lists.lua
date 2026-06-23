-- LSP symbol lists and references (document symbols, workspace symbols, references).

local open = require("lsp-nav.open")

local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "LSP" })
end

local function supports(client, method, buffer)
  local ok, supported = pcall(function()
    return client:supports_method(method, { bufnr = buffer })
  end)
  return ok and supported
end

local function clients_for(method, buffer)
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buffer })) do
    if supports(client, method, buffer) then
      clients[#clients + 1] = client
    end
  end
  return clients
end

local function open_qflist(items, title)
  if #items == 0 then
    notify(title .. ": no results", vim.log.levels.WARN)
    return
  end
  vim.fn.setqflist({}, " ", { title = title, items = items })
  vim.cmd("copen")
end

local function item_label(item)
  local filename = item.filename or item.path or ""
  local rel = filename ~= "" and vim.fn.fnamemodify(filename, ":~:.") or "[unknown]"
  local text = item.text or item.label or ""
  return string.format("%s:%d:%d  %s", rel, item.lnum or 1, item.col or 1, text)
end

local function open_location(item)
  local filename = item and (item.filename or item.path)
  if type(filename) ~= "string" or filename == "" then return end
  open.file(filename, item.lnum or 1, item.col or 1)
end

local function open_picker(items, title)
  if #items == 0 then
    notify(title .. ": no results", vim.log.levels.WARN)
    return
  end

  local on_select = M._picker_fn
  if not on_select then
    local ok, picker = pcall(require, "picker")
    if ok and picker.select_items then on_select = picker.select_items end
  end

  if on_select then
    on_select(items, {
      prompt = title,
      quickfix_title = title,
      input_mode = true,
      format_item = item_label,
      preview = function(item) return item.filename end,
      preview_lnum = function(item) return item.lnum end,
    }, open_location)
    return
  end

  -- Fallback: quickfix
  open_qflist(items, title)
end

local function symbol_kind(kind)
  return vim.lsp.protocol.SymbolKind[kind] or "Symbol"
end

local function symbol_item(symbol, uri, depth)
  -- DocumentSymbol has .selectionRange/.range; SymbolInformation (workspace) uses .location.range
  local range = symbol.selectionRange or symbol.range
    or (symbol.location and symbol.location.range)
  if not range or not range.start then return nil end

  local filename = vim.uri_to_fname(symbol.location and symbol.location.uri or uri)
  local location_range = symbol.location and symbol.location.range or range
  local indent = string.rep("  ", depth or 0)
  return {
    filename = filename,
    lnum = location_range.start.line + 1,
    col = location_range.start.character + 1,
    text = indent .. symbol.name .. " [" .. symbol_kind(symbol.kind) .. "]",
  }
end

local function collect_document_symbols(result, uri, items, depth)
  for _, symbol in ipairs(result or {}) do
    local item = symbol_item(symbol, uri, depth)
    if item then items[#items + 1] = item end
    if type(symbol.children) == "table" then
      collect_document_symbols(symbol.children, uri, items, (depth or 0) + 1)
    end
  end
end

local function collect_workspace_symbols(result, items)
  for _, symbol in ipairs(result or {}) do
    local item = symbol_item(symbol, symbol.location and symbol.location.uri or "", 0)
    if item then items[#items + 1] = item end
  end
end

local function request_all(method, params, title, collector)
  local buffer = vim.api.nvim_get_current_buf()
  local clients = clients_for(method, buffer)
  if #clients == 0 then
    notify(title .. ": no attached client supports " .. method, vim.log.levels.WARN)
    return
  end

  local remaining = #clients
  local items = {}

  for _, client in ipairs(clients) do
    client:request(method, params, function(error, result)
      if error then
        notify(error.message or tostring(error), vim.log.levels.WARN)
      elseif result then
        collector(result, items, client)
      end

      remaining = remaining - 1
      if remaining == 0 then
        vim.schedule(function()
          open_picker(items, title)
        end)
      end
    end, buffer)
  end
end

function M.references()
  vim.lsp.buf.references(nil, {
    on_list = function(options)
      open_picker(options.items or {}, "LSP References")
    end,
  })
end

function M.document_symbols()
  local buffer = vim.api.nvim_get_current_buf()
  local uri = vim.uri_from_bufnr(buffer)
  local params = { textDocument = vim.lsp.util.make_text_document_params(buffer) }

  request_all("textDocument/documentSymbol", params, "Document Symbols", function(result, items)
    collect_document_symbols(result, uri, items, 0)
  end)
end

function M.workspace_symbols()
  local on_select = M._picker_fn
  if not on_select then
    local ok, picker = pcall(require, "picker")
    if ok and picker.select_items then on_select = picker.select_items end
  end

  local buffer = vim.api.nvim_get_current_buf()
  local lsp_clients = clients_for("workspace/symbol", buffer)

  local function do_query(q, callback)
    if #lsp_clients == 0 then
      vim.schedule(function() callback({}) end)
      return
    end
    local remaining = #lsp_clients
    local items = {}
    for _, client in ipairs(lsp_clients) do
      client:request("workspace/symbol", { query = q }, function(err, result)
        if not err and result then
          collect_workspace_symbols(result, items)
        end
        remaining = remaining - 1
        if remaining == 0 then
          vim.schedule(function() callback(items) end)
        end
      end, buffer)
    end
  end

  if not on_select then
    local query = vim.fn.input("Workspace symbol: ")
    if vim.trim(query) == "" then return end
    do_query(query, function(items)
      open_picker(items, "Workspace Symbols")
    end)
    return
  end

  -- Pre-fetch with "*" — works as wildcard on jdtls and returns all symbols
  -- on vtsls/tsserver. Falls back gracefully to input_only if server rejects it.
  do_query("*", function(initial_items)
    on_select(initial_items, {
      prompt = "Workspace Symbols",
      input_mode = true,
      input_only = #initial_items == 0,
      debounce_ms = 180,
      format_item = item_label,
      preview = function(item) return item.filename end,
      preview_lnum = function(item) return item.lnum end,
      dynamic_items = function(state, callback)
        do_query(vim.trim(state.query or ""), callback)
      end,
    }, open_location)
  end)
end

--- Set a custom picker function for document symbols and references.
--- @param fn function(items, opts, on_select) Compatible with select_items API.
function M.set_picker(fn)
  M._picker_fn = fn
end

--- Internal test helpers (only used by tests).
M._test = {
  symbol_item = symbol_item,
  collect_document_symbols = collect_document_symbols,
  collect_workspace_symbols = collect_workspace_symbols,
}

return M
