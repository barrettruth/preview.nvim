local M = {}

local log = require('preview.log')

local ns = vim.api.nvim_create_namespace('preview')

---@param bufnr integer
function M.clear(bufnr)
  vim.diagnostic.set(ns, bufnr, {})
  log.dbg('cleared diagnostics for buffer %d', bufnr)
end

---@param bufnr integer
---@param name string
---@param error_parser fun(stderr: string, ctx: preview.Context): preview.Diagnostic[]
---@param stderr string
---@param ctx preview.Context
function M.set(bufnr, name, error_parser, stderr, ctx)
  local ok, diagnostics = pcall(error_parser, stderr, ctx)
  if not ok then
    log.dbg('error_parser for "%s" failed: %s', name, diagnostics)
    return
  end
  if not diagnostics or #diagnostics == 0 then
    log.dbg('error_parser for "%s" returned no diagnostics', name)
    return
  end
  for _, d in ipairs(diagnostics) do
    d.source = d.source or name
  end
  vim.diagnostic.set(ns, bufnr, diagnostics)
  log.dbg('set %d diagnostics for buffer %d from provider "%s"', #diagnostics, bufnr, name)
end

---@return integer
function M.get_namespace()
  return ns
end

return M
