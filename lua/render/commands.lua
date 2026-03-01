local M = {}

local subcommands = { 'compile', 'stop', 'clean', 'status' }

---@param args string
local function dispatch(args)
  local subcmd = args ~= '' and args or 'compile'

  if subcmd == 'compile' then
    require('render').compile()
  elseif subcmd == 'stop' then
    require('render').stop()
  elseif subcmd == 'clean' then
    require('render').clean()
  elseif subcmd == 'status' then
    local s = require('render').status()
    if s.compiling then
      vim.notify('[render.nvim] compiling with "' .. s.provider .. '"', vim.log.levels.INFO)
    else
      vim.notify('[render.nvim] idle', vim.log.levels.INFO)
    end
  else
    vim.notify('[render.nvim] unknown subcommand: ' .. subcmd, vim.log.levels.ERROR)
  end
end

---@param lead string
---@return string[]
local function complete(lead)
  return vim.tbl_filter(function(s)
    return s:find(lead, 1, true) == 1
  end, subcommands)
end

function M.setup()
  vim.api.nvim_create_user_command('Render', function(opts)
    dispatch(opts.args)
  end, {
    nargs = '?',
    complete = function(lead)
      return complete(lead)
    end,
    desc = 'Compile, stop, clean, or check status of document rendering',
  })
end

return M
