local M = {}

local subcommands = { 'compile', 'stop', 'clean', 'watch', 'status' }

---@param args string
local function dispatch(args)
  local subcmd = args ~= '' and args or 'compile'

  if subcmd == 'compile' then
    require('preview').compile()
  elseif subcmd == 'stop' then
    require('preview').stop()
  elseif subcmd == 'clean' then
    require('preview').clean()
  elseif subcmd == 'watch' then
    require('preview').watch()
  elseif subcmd == 'status' then
    local s = require('preview').status()
    local parts = {}
    if s.compiling then
      table.insert(parts, 'compiling with "' .. s.provider .. '"')
    else
      table.insert(parts, 'idle')
    end
    if s.watching then
      table.insert(parts, 'watching')
    end
    vim.notify('[preview.nvim] ' .. table.concat(parts, ', '), vim.log.levels.INFO)
  else
    vim.notify('[preview.nvim] unknown subcommand: ' .. subcmd, vim.log.levels.ERROR)
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
  vim.api.nvim_create_user_command('Preview', function(opts)
    dispatch(opts.args)
  end, {
    nargs = '?',
    complete = function(lead)
      return complete(lead)
    end,
    desc = 'Compile, stop, clean, watch, or check status of document preview',
  })
end

return M
