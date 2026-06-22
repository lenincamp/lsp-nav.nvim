local M = {}

local function same_path(a, b)
  if not a or not b or a == "" or b == "" then
    return false
  end
  return vim.fs.normalize(a) == vim.fs.normalize(b)
end

--- Open a file, prompting to save when the current buffer is modified.
--- @param path string
--- @param lnum number|nil 1-based line
--- @param col number|nil 1-based column
--- @return boolean opened true when the target file is active
function M.file(path, lnum, col)
  if type(path) ~= "string" or path == "" then
    return false
  end

  path = vim.fs.normalize(path)
  local escaped = vim.fn.fnameescape(path)
  if vim.bo.modified then
    vim.cmd("confirm edit " .. escaped)
  else
    vim.cmd("edit " .. escaped)
  end

  if not same_path(vim.api.nvim_buf_get_name(0), path) then
    return false
  end

  if lnum then
    pcall(vim.api.nvim_win_set_cursor, 0, { lnum, math.max((col or 1) - 1, 0) })
  end
  return true
end

return M
