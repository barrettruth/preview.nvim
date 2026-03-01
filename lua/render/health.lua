local M = {}

function M.check()
  vim.health.start('render.nvim')

  if vim.fn.has('nvim-0.10.0') == 1 then
    vim.health.ok('Neovim 0.10.0+ detected')
  else
    vim.health.error('render.nvim requires Neovim 0.10.0+')
  end

  local config = require('render').get_config()

  local provider_count = vim.tbl_count(config.providers)
  if provider_count == 0 then
    vim.health.warn('no providers configured')
  else
    vim.health.ok(provider_count .. ' provider(s) configured')
  end

  for name, provider in pairs(config.providers) do
    local bin = provider.cmd[1]
    if vim.fn.executable(bin) == 1 then
      vim.health.ok('provider "' .. name .. '": ' .. bin .. ' found')
    else
      vim.health.error('provider "' .. name .. '": ' .. bin .. ' not found')
    end
  end

  local ft_count = vim.tbl_count(config.providers_by_ft)
  if ft_count > 0 then
    for ft, name in pairs(config.providers_by_ft) do
      if config.providers[name] then
        vim.health.ok('filetype "' .. ft .. '" -> provider "' .. name .. '"')
      else
        vim.health.error('filetype "' .. ft .. '" maps to unknown provider "' .. name .. '"')
      end
    end
  end
end

return M
