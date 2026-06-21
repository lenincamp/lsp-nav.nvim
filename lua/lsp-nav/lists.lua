-- LSP symbol lists and references (document symbols, workspace symbols, references).

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
  vim.cmd("edit " .. vim.fn.fnameescape(filename))
  vim.api.nvim_win_set_cursor(0, { item.lnum or 1, math.max((item.col or 1) - 1, 0) })
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
  local range = symbol.selectionRange or symbol.range
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
  vim.ui.input({ prompt = "Workspace symbol: " }, function(query)
    if not query or query == "" then return end
    request_all("workspace/symbol", { query = query }, "Workspace Symbols", function(result, items)
      collect_workspace_symbols(result, items)
    end)
  end)
end

--- Set a custom picker function for document symbols and references.
--- @param fn function(items, opts, on_select) Compatible with select_items API.
function M.set_picker(fn)
  M._picker_fn = fn
end

return M
