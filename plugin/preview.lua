if vim.g.loaded_preview then
  return
end
vim.g.loaded_preview = 1

require('preview.commands').setup()
require('preview.mappings').setup()

pcall(function()
  require('preview.migration').warn_if_github_source()
end)

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    require('preview.compiler').stop_all()
  end,
})
