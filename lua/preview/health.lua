local M = {}

function M.check()
  vim.health.start('preview.nvim')

  if vim.fn.has('nvim-0.11.0') == 1 then
    vim.health.ok('Neovim 0.11.0+ detected')
  else
    vim.health.error('preview.nvim requires Neovim 0.11.0+')
  end

  local config = require('preview').get_config()

  local provider_count = vim.tbl_count(config.providers)
  if provider_count == 0 then
    vim.health.warn('no providers configured')
  else
    vim.health.ok(provider_count .. ' provider(s) configured')
  end

  for ft, provider in pairs(config.providers) do
    local bin = provider.cmd[1]
    if vim.fn.executable(bin) == 1 then
      vim.health.ok('filetype "' .. ft .. '": ' .. bin .. ' found')
    else
      vim.health.error('filetype "' .. ft .. '": ' .. bin .. ' not found')
    end
  end
end

return M
