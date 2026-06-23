local lists = require("lsp-nav.lists")
local t = lists._test

local URI = "file:///src/Foo.java"
local function range(l, c) return { start = { line = l, character = c }, ["end"] = { line = l, character = c + 5 } } end

describe("lsp-nav.lists symbol_item", function()

  -- ── DocumentSymbol (textDocument/documentSymbol) ───────────────────────────
  -- Has top-level .selectionRange and .range — no .location

  it("DocumentSymbol with selectionRange → produces item at selectionRange line", function()
    local sym = {
      name = "MyClass",
      kind = 5, -- Class
      selectionRange = range(9, 6),
      range = range(9, 0),
    }
    local item = t.symbol_item(sym, URI, 0)
    assert.is_not_nil(item)
    assert.equals(10, item.lnum)   -- 0-indexed 9 → 10
    assert.equals(7, item.col)     -- 0-indexed 6 → 7
    assert.truthy(item.text:find("MyClass"))
    assert.truthy(item.text:find("Class"))
  end)

  it("DocumentSymbol with only .range (no selectionRange) → produces item", function()
    local sym = { name = "helperFn", kind = 12, range = range(3, 2) }
    local item = t.symbol_item(sym, URI, 0)
    assert.is_not_nil(item)
    assert.equals(4, item.lnum)
  end)

  it("DocumentSymbol indent matches depth", function()
    local sym = { name = "field", kind = 8, selectionRange = range(0, 0) }
    local item = t.symbol_item(sym, URI, 2)
    assert.is_not_nil(item)
    assert.truthy(item.text:sub(1, 4) == "    ") -- 2 levels × 2 spaces
  end)

  -- ── SymbolInformation (workspace/symbol) ───────────────────────────────────
  -- Has .location.range — NO top-level .range or .selectionRange
  -- BUG BEFORE FIX: symbol_item returned nil for ALL workspace symbols

  it("SymbolInformation → produces item using location.range (regression)", function()
    local sym = {
      name = "UserService",
      kind = 5,
      -- deliberately NO .range or .selectionRange at top level
      location = { uri = URI, range = range(41, 13) },
    }
    local item = t.symbol_item(sym, URI, 0)
    assert.is_not_nil(item, "BUG: symbol_item must not return nil for SymbolInformation")
    assert.equals(42, item.lnum)   -- 0-indexed 41 → 42
    assert.equals(14, item.col)    -- 0-indexed 13 → 14
    assert.truthy(item.text:find("UserService"))
  end)

  it("SymbolInformation with different uri → filename from location.uri", function()
    local other_uri = "file:///src/OtherFile.java"
    local sym = {
      name = "OrderRepo",
      kind = 5,
      location = { uri = other_uri, range = range(0, 0) },
    }
    local item = t.symbol_item(sym, URI, 0)
    assert.is_not_nil(item)
    assert.truthy(item.filename:find("OtherFile"))
  end)

  -- ── Edge cases ─────────────────────────────────────────────────────────────

  it("symbol with no range anywhere → returns nil", function()
    local sym = { name = "Ghost", kind = 5 }
    assert.is_nil(t.symbol_item(sym, URI, 0))
  end)

  it("WorkspaceSymbol with location but no range → returns nil", function()
    local sym = { name = "Partial", kind = 5, location = { uri = URI } }
    assert.is_nil(t.symbol_item(sym, URI, 0))
  end)
end)

describe("lsp-nav.lists collect_workspace_symbols", function()

  it("collects all SymbolInformation entries", function()
    local syms = {
      { name = "Alpha", kind = 5, location = { uri = URI, range = range(0, 0) } },
      { name = "Beta",  kind = 6, location = { uri = URI, range = range(5, 0) } },
    }
    local items = {}
    t.collect_workspace_symbols(syms, items)
    assert.equals(2, #items)
    assert.equals(1,  items[1].lnum)
    assert.equals(6,  items[2].lnum)
  end)

  it("skips symbols with no range", function()
    local syms = {
      { name = "Good", kind = 5, location = { uri = URI, range = range(0, 0) } },
      { name = "Bad",  kind = 5, location = { uri = URI } },
    }
    local items = {}
    t.collect_workspace_symbols(syms, items)
    assert.equals(1, #items)
    assert.truthy(items[1].text:find("Good"))
  end)
end)

describe("lsp-nav.lists collect_document_symbols", function()

  it("collects nested children with increasing indent", function()
    local child = { name = "method", kind = 6, selectionRange = range(2, 4) }
    local parent = { name = "MyClass", kind = 5, selectionRange = range(0, 0), children = { child } }
    local items = {}
    t.collect_document_symbols({ parent }, URI, items, 0)
    assert.equals(2, #items)
    assert.equals("MyClass [Class]", items[1].text)
    assert.truthy(items[2].text:sub(1, 2) == "  ") -- 1 level indent
  end)
end)
