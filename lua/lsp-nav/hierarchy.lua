-- Call Hierarchy: interactive tree browser for incoming/outgoing calls.

local M = {}

local PREPARE = "textDocument/prepareCallHierarchy"

-- ── Tree rendering ────────────────────────────────────────────────────

local function tree_marker(node)
  if node.loading then return "..." end
  if node.children == nil then return ">" end
  if #node.children > 0 then
    return node.expanded and "v" or ">"
  end
  return " "
end

local function tree_lines(root, label_fn)
  local lines = {}
  local line_nodes = {}

  local function append(node)
    local indent = string.rep("  ", node.depth or 0)
    lines[#lines + 1] = string.format("%s%s %s", indent, tree_marker(node), label_fn(node))
    line_nodes[#lines] = node
    if node.expanded and node.children then
      for _, child in ipairs(node.children) do
        append(child)
      end
    end
  end

  append(root)
  return lines, line_nodes
end

-- ── Model helpers ─────────────────────────────────────────────────────

local function item_range(item)
  return item and (item.selectionRange or item.range) or nil
end

local function item_line(item)
  local range = item_range(item)
  return range and range.start and (range.start.line + 1) or 1
end

local function item_col(item)
  local range = item_range(item)
  return range and range.start and range.start.character or 0
end

local function item_file(item)
  if not item or type(item.uri) ~= "string" then return "" end
  local ok, name = pcall(vim.uri_to_fname, item.uri)
  if not ok or type(name) ~= "string" then return item.uri end
  return vim.fn.fnamemodify(name, ":~:.")
end

local function item_label(item)
  if not item then return "<unknown>" end
  local name = item.name or "<anonymous>"
  local detail = item.detail and vim.trim(item.detail) or ""
  local file = item_file(item)
  local file_part = file ~= "" and ("  " .. vim.fn.fnamemodify(file, ":t") .. ":" .. item_line(item)) or ""
  if detail ~= "" and detail ~= name then
    return name .. "  " .. detail .. file_part
  end
  return name .. file_part
end

local function make_node(item, depth, parent)
  return {
    item = item,
    depth = depth or 0,
    parent = parent,
    expanded = false,
    loading = false,
    children = nil,
  }
end

local function call_method(direction)
  return direction == "outgoing" and "callHierarchy/outgoingCalls" or "callHierarchy/incomingCalls"
end

local function call_item(direction, call)
  return direction == "outgoing" and call.to or call.from
end

-- ── State ─────────────────────────────────────────────────────────────

local state = {
  bufnr = nil,
  win = nil,
  source_bufnr = nil,
  source_win = nil,
  client = nil,
  root = nil,
  direction = "incoming",
  line_nodes = {},
  help = false,
}

local function is_valid_buf(bufnr)
  return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function is_valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

-- ── Rendering ─────────────────────────────────────────────────────────

local function render()
  if not state.root then return end

  local bufnr = state.bufnr
  if not is_valid_buf(bufnr) then return end

  local direction = state.direction == "outgoing" and "outgoing" or "incoming"
  local header = {
    "Call Hierarchy [" .. direction .. "]",
    "<CR> jump  o/<Tab> expand  i incoming  O outgoing  r refresh  Q quickfix  q close  ? help",
    "",
  }

  if state.help then
    header[#header + 1] = "Native LSP methods: " .. PREPARE .. ", " .. call_method(state.direction)
    header[#header + 1] = "The tree is resolved lazily; expand a node to request its children."
    header[#header + 1] = ""
  end

  local body_lines, body_nodes = tree_lines(state.root, function(node) return item_label(node.item) end)
  local lines = {}
  vim.list_extend(lines, header)
  local offset = #header
  vim.list_extend(lines, body_lines)

  state.line_nodes = {}
  for line, node in pairs(body_nodes) do
    state.line_nodes[offset + line] = node
  end

  local win = is_valid_win(state.win) and state.win or nil
  local cursor_line = win and vim.api.nvim_win_get_cursor(win)[1] or 1

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  if win then
    pcall(vim.api.nvim_win_set_cursor, win, { math.min(cursor_line, #lines), 0 })
  end
end

-- ── LSP requests ──────────────────────────────────────────────────────

local function request_children(node)
  if not state.client or node.loading then return end

  node.loading = true
  node.expanded = true
  render()

  state.client:request(call_method(state.direction), { item = node.item }, function(err, result)
    vim.schedule(function()
      node.loading = false
      if err then
        node.children = {}
        vim.notify("Call hierarchy request failed: " .. tostring(err.message or err), vim.log.levels.WARN)
        render()
        return
      end

      node.children = {}
      for _, call in ipairs(result or {}) do
        local item = call_item(state.direction, call)
        if item then
          node.children[#node.children + 1] = make_node(item, node.depth + 1, node)
        end
      end
      node.expanded = #node.children > 0
      render()
    end)
  end, state.source_bufnr)
end

-- ── Buffer & window ───────────────────────────────────────────────────

local function ensure_buffer()
  if is_valid_buf(state.bufnr) then return state.bufnr end

  local bufnr = vim.api.nvim_create_buf(false, true)
  state.bufnr = bufnr
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].filetype = "call_hierarchy"
  pcall(vim.api.nvim_buf_set_name, bufnr, "Call Hierarchy")
  return bufnr
end

local function setup_keymaps(bufnr)
  if vim.b[bufnr].lsp_nav_hierarchy_keymaps then return end
  local opts = { buffer = bufnr, silent = true, nowait = true }
  local function set(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
  end

  set("<CR>", function() M.jump() end, "Call hierarchy: jump")
  set("o", function() M.toggle_node() end, "Call hierarchy: expand")
  set("<Tab>", function() M.toggle_node() end, "Call hierarchy: expand")
  set("za", function() M.toggle_node() end, "Call hierarchy: expand")
  set("i", function() M.set_direction("incoming") end, "Call hierarchy: incoming")
  set("O", function() M.set_direction("outgoing") end, "Call hierarchy: outgoing")
  set("r", function() M.refresh() end, "Call hierarchy: refresh")
  set("q", function() M.close() end, "Call hierarchy: close")
  set("?", function() M.toggle_help() end, "Call hierarchy: help")
  set("Q", function() M.to_quickfix() end, "Call hierarchy: quickfix")

  vim.b[bufnr].lsp_nav_hierarchy_keymaps = true
end

local function ensure_window()
  local bufnr = ensure_buffer()
  if is_valid_win(state.win) then return state.win end

  vim.cmd("botright new")
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, bufnr)
  vim.api.nvim_win_set_height(state.win, math.min(18, math.max(10, math.floor(vim.o.lines * 0.28))))
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].wrap = false
  vim.wo[state.win].cursorline = true
  return state.win
end

-- ── Actions ───────────────────────────────────────────────────────────

local function selected_node()
  if not is_valid_win(state.win) then return nil end
  local lnum = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.line_nodes[lnum]
end

function M.jump()
  local node = selected_node()
  if not node or not node.item or type(node.item.uri) ~= "string" then return end

  local loc = { uri = node.item.uri, range = item_range(node.item) }
  if is_valid_win(state.source_win) then
    vim.api.nvim_set_current_win(state.source_win)
  end
  if state.client then
    pcall(vim.lsp.util.show_document, loc, state.client.offset_encoding or "utf-16", { focus = true })
  else
    local bufnr = vim.uri_to_bufnr(node.item.uri)
    vim.fn.bufload(bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    pcall(vim.api.nvim_win_set_cursor, 0, { item_line(node.item), item_col(node.item) })
  end
end

function M.toggle_node()
  local node = selected_node()
  if not node then return end
  if node.children == nil then
    request_children(node)
    return
  end
  if #node.children == 0 then return end
  node.expanded = not node.expanded
  render()
end

function M.set_direction(direction)
  direction = direction == "outgoing" and "outgoing" or "incoming"
  if state.direction == direction and state.root and state.root.children ~= nil then return end
  state.direction = direction
  if state.root then
    state.root.children = nil
    state.root.expanded = false
    request_children(state.root)
  end
end

function M.refresh()
  if not state.root then return end
  state.root.children = nil
  state.root.expanded = false
  request_children(state.root)
end

function M.toggle_help()
  state.help = not state.help
  render()
end

function M.close()
  if is_valid_win(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
end

function M.to_quickfix()
  local items = {}
  local line_count = is_valid_buf(state.bufnr) and vim.api.nvim_buf_line_count(state.bufnr) or 0
  for lnum = 1, line_count do
    local node = state.line_nodes[lnum]
    local item = node and node.item or nil
    if item and item.uri then
      items[#items + 1] = {
        filename = item_file(item),
        lnum = item_line(item),
        col = item_col(item) + 1,
        text = string.rep("  ", node.depth) .. item_label(item),
      }
    end
  end

  if #items == 0 then
    vim.notify("Call hierarchy has no visible nodes", vim.log.levels.INFO)
    return
  end

  vim.fn.setqflist({}, "r", { title = "Call Hierarchy [" .. state.direction .. "]", items = items })
  vim.cmd("copen")
end

-- ── Client selection ──────────────────────────────────────────────────

local function supports_method(client, method, bufnr)
  local ok, supported = pcall(function()
    return client:supports_method(method, bufnr)
  end)
  return ok and supported
end

local function select_client(bufnr, on_choice)
  local clients = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if supports_method(client, PREPARE, bufnr) then
      clients[#clients + 1] = client
    end
  end

  if #clients == 0 then
    vim.notify("No LSP client supports call hierarchy for this buffer", vim.log.levels.WARN)
    return
  end
  if #clients == 1 then
    on_choice(clients[1])
    return
  end

  vim.ui.select(clients, {
    prompt = "Call hierarchy client:",
    format_item = function(client) return client.name end,
  }, function(client)
    if client then on_choice(client) end
  end)
end

-- ── Entry points ──────────────────────────────────────────────────────

function M.open(direction)
  direction = direction == "outgoing" and "outgoing" or "incoming"
  local source_bufnr = vim.api.nvim_get_current_buf()
  local source_win = vim.api.nvim_get_current_win()
  local source_cursor = vim.api.nvim_win_get_cursor(source_win)

  select_client(source_bufnr, function(client)
    if not client then return end

    local params = vim.lsp.util.make_position_params(source_win, client.offset_encoding or "utf-16")
    if not params then
      vim.notify("Call hierarchy source buffer is no longer available", vim.log.levels.WARN)
      return
    end

    client:request(PREPARE, params, function(err, result)
      vim.schedule(function()
        if err then
          vim.notify("Call hierarchy prepare failed: " .. tostring(err.message or err), vim.log.levels.WARN)
          return
        end

        if type(result) ~= "table" or #result == 0 then
          vim.notify("No call hierarchy item at cursor", vim.log.levels.INFO)
          return
        end

        local item = result[1]

        state.source_bufnr = source_bufnr
        state.source_win = source_win
        state.client = client
        state.direction = direction
        state.root = make_node(item, 0, nil)

        local bufnr = ensure_buffer()
        setup_keymaps(bufnr)
        ensure_window()
        render()
        request_children(state.root)
      end)
    end, source_bufnr)
  end)
end

function M.incoming()
  M.open("incoming")
end

function M.outgoing()
  M.open("outgoing")
end

return M
