if vim.g.loaded_preview then
  return
end
vim.g.loaded_preview = 1

require('preview.commands').setup()

vim.keymap.set('n', '<Plug>(preview-toggle)', function()
  require('preview').toggle()
end, { silent = true, desc = 'Toggle document preview' })
vim.keymap.set('n', '<Plug>(preview-compile)', function()
  require('preview').compile()
end, { silent = true, desc = 'Compile document preview once' })
vim.keymap.set('n', '<Plug>(preview-open)', function()
  require('preview').open()
end, { silent = true, desc = 'Open document preview output' })
vim.keymap.set('n', '<Plug>(preview-output)', function()
  require('preview').output()
end, { silent = true, desc = 'Show document preview compiler output' })
vim.keymap.set('n', '<Plug>(preview-clean)', function()
  require('preview').clean()
end, { silent = true, desc = 'Clean document preview artifacts' })

pcall(function()
  require('preview.migration').warn_if_github_source()
end)

vim.api.nvim_create_autocmd('VimLeavePre', {
  callback = function()
    require('preview.compiler').stop_all()
  end,
})
