-- Tests: workspace_symbols() picker opts depending on server query behavior.
-- Simulates vtsls-like (responds to "") and jdtls-like (empty "" → no results).
local lists = require("lsp-nav.lists")

local URI = "file:///src/Test.java"
local function range(l) return { start = { line = l, character = 0 }, ["end"] = { line = l, character = 5 } } end

local function sym(name, line)
  return { name = name, kind = 5, location = { uri = URI, range = range(line) } }
end

-- Build a fake LSP client that responds to workspace/symbol.
-- response_fn(query) -> table|nil
local function fake_client(response_fn)
  return {
    supports_method = function() return true end,
    request = function(_, method, params, cb, _)
      if method == "workspace/symbol" then
        local result = response_fn(params.query)
        -- simulate async response via vim.schedule
        vim.schedule(function() cb(nil, result) end)
      end
    end,
  }
end

-- Capture what workspace_symbols() passes to the picker.
local function capture_picker_call(client, timeout_ms)
  local captured = {}
  local done = false

  lists.set_picker(function(initial_items, opts, _)
    captured.initial_items = initial_items
    captured.opts = opts
    done = true
  end)

  local orig = vim.lsp.get_clients
  vim.lsp.get_clients = function() return { client } end

  lists.workspace_symbols()
  vim.wait(timeout_ms or 300, function() return done end)

  vim.lsp.get_clients = orig
  return captured
end

-- ─── vtsls-like: returns symbols for "" and "*" ──────────────────────────────

describe("workspace_symbols — vtsls-like server (responds to empty query and '*')", function()
  local all = { sym("Alpha", 0), sym("Beta", 5), sym("Gamma", 10) }
  local client = fake_client(function(q)
    -- TypeScript server: "" and "*" both return all workspace symbols
    if q == "" or q == "*" then return all end
    local results = {}
    for _, s in ipairs(all) do
      if s.name:lower():sub(1, #q) == q:lower() then results[#results + 1] = s end
    end
    return results
  end)

  it("initial_items is non-empty (server returned symbols for '')", function()
    local c = capture_picker_call(client)
    assert.is_not_nil(c.initial_items)
    assert.equals(3, #c.initial_items)
  end)

  it("input_only = false (symbols present on open)", function()
    local c = capture_picker_call(client)
    assert.is_false(c.opts.input_only)
  end)

  it("input_mode = true (search input visible)", function()
    local c = capture_picker_call(client)
    assert.is_true(c.opts.input_mode)
  end)

  it("dynamic_items returns filtered results for a typed query", function()
    local c = capture_picker_call(client)
    local dyn_result
    c.opts.dynamic_items({ query = "Al" }, function(items) dyn_result = items end)
    vim.wait(300, function() return dyn_result ~= nil end)
    assert.is_not_nil(dyn_result)
    assert.equals(1, #dyn_result)
    assert.truthy(dyn_result[1].text:find("Alpha"))
  end)

  it("items have correct lnum (1-indexed)", function()
    local c = capture_picker_call(client)
    assert.equals(1,  c.initial_items[1].lnum)
    assert.equals(6,  c.initial_items[2].lnum)
    assert.equals(11, c.initial_items[3].lnum)
  end)
end)

-- ─── jdtls-like: returns nothing for "", responds to non-empty ───────────────

describe("workspace_symbols — jdtls-like server (empty query returns nothing)", function()
  local all_syms = { sym("OrderService", 0), sym("OrderRepository", 10), sym("UserService", 20) }
  local client = fake_client(function(q)
    if q == "" then return {} end  -- jdtls does not respond to ""
    local results = {}
    for _, s in ipairs(all_syms) do
      if s.name:lower():find(q:lower(), 1, true) then
        results[#results + 1] = s
      end
    end
    return results
  end)

  it("initial_items is empty (server returned nothing for '')", function()
    local c = capture_picker_call(client)
    assert.is_not_nil(c.initial_items)
    assert.equals(0, #c.initial_items)
  end)

  it("input_only = true (picker opens with input focus, no initial items)", function()
    local c = capture_picker_call(client)
    assert.is_true(c.opts.input_only)
  end)

  it("input_mode = true even when no initial items", function()
    local c = capture_picker_call(client)
    assert.is_true(c.opts.input_mode)
  end)

  it("dynamic_items returns results when user types", function()
    local c = capture_picker_call(client)
    local dyn_result
    c.opts.dynamic_items({ query = "Order" }, function(items) dyn_result = items end)
    vim.wait(300, function() return dyn_result ~= nil end)
    assert.is_not_nil(dyn_result)
    assert.equals(2, #dyn_result)
  end)

  it("dynamic_items returns nothing for empty query (consistent with server)", function()
    local c = capture_picker_call(client)
    local dyn_result
    c.opts.dynamic_items({ query = "" }, function(items) dyn_result = items end)
    vim.wait(300, function() return dyn_result ~= nil end)
    assert.equals(0, #dyn_result)
  end)

  it("dynamic_items: lnum is correct for returned items", function()
    local c = capture_picker_call(client)
    local dyn_result
    c.opts.dynamic_items({ query = "UserService" }, function(items) dyn_result = items end)
    vim.wait(300, function() return dyn_result ~= nil end)
    assert.equals(1, #dyn_result)
    assert.equals(21, dyn_result[1].lnum) -- line 20 (0-indexed) → 21
  end)
end)

-- ─── wildcard prefetch: both servers return all symbols for "*" ───────────────

describe("workspace_symbols — '*' as prefetch query", function()
  local all_syms = { sym("Foo", 0), sym("Bar", 1), sym("Baz", 2) }

  -- jdtls-like: rejects "", accepts "*"
  local jdtls_client = fake_client(function(q)
    if q == "" then return {} end
    if q == "*" then return all_syms end
    local r = {}
    for _, s in ipairs(all_syms) do
      if s.name:lower():find(q:lower(), 1, true) then r[#r+1] = s end
    end
    return r
  end)

  -- vtsls-like: accepts both "" and "*" (TypeScript server does substring match, "*" matches all)
  local vtsls_client = fake_client(function(q)
    if q == "" or q == "*" then return all_syms end
    local r = {}
    for _, s in ipairs(all_syms) do
      if s.name:lower():find(q:lower(), 1, true) then r[#r+1] = s end
    end
    return r
  end)

  it("jdtls: '*' prefetch returns all symbols → input_only = false", function()
    local orig = vim.lsp.get_clients
    vim.lsp.get_clients = function() return { jdtls_client } end
    local captured = {}
    local done = false
    lists.set_picker(function(items, opts) captured.items = items; captured.opts = opts; done = true end)
    lists.workspace_symbols()
    vim.wait(300, function() return done end)
    vim.lsp.get_clients = orig

    assert.equals(3, #captured.items)
    assert.is_false(captured.opts.input_only)
  end)

  it("vtsls: '*' prefetch returns all workspace symbols → input_only = false", function()
    local orig = vim.lsp.get_clients
    vim.lsp.get_clients = function() return { vtsls_client } end
    local captured = {}
    local done = false
    lists.set_picker(function(items, opts) captured.items = items; captured.opts = opts; done = true end)
    lists.workspace_symbols()
    vim.wait(300, function() return done end)
    vim.lsp.get_clients = orig

    assert.equals(3, #captured.items)
    assert.is_false(captured.opts.input_only)
  end)

  it("dynamic_items still fires typed queries after '*' prefetch", function()
    local orig = vim.lsp.get_clients
    vim.lsp.get_clients = function() return { jdtls_client } end
    local captured = {}
    local done = false
    lists.set_picker(function(items, opts) captured.items = items; captured.opts = opts; done = true end)
    lists.workspace_symbols()
    vim.wait(300, function() return done end)
    vim.lsp.get_clients = orig

    local dyn
    captured.opts.dynamic_items({ query = "Foo" }, function(items) dyn = items end)
    vim.wait(300, function() return dyn ~= nil end)
    assert.equals(1, #dyn)
    assert.truthy(dyn[1].text:find("Foo"))
  end)
end)
