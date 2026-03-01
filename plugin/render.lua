if vim.g.loaded_render then
  return
end
vim.g.loaded_render = 1

require('render.commands').setup()

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    require('render.compiler').stop_all()
  end,
})
