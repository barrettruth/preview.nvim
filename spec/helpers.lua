local plugin_dir = vim.fn.getcwd()
vim.opt.runtimepath:prepend(plugin_dir)
vim.opt.packpath = {}

local M = {}

function M.create_buffer(lines, ft)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines or {})
  if ft then
    vim.bo[bufnr].filetype = ft
  end
  return bufnr
end

function M.delete_buffer(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

function M.reset_config(opts)
  vim.g.preview = opts
  require('preview')._test.reset()
end

return M
