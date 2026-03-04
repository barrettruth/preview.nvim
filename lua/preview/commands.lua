local M = {}

local handlers = {
  compile = function()
    require('preview').compile()
  end,
  stop = function()
    require('preview').stop()
  end,
  clean = function()
    require('preview').clean()
  end,
  toggle = function()
    require('preview').toggle()
  end,
  open = function()
    require('preview').open()
  end,
  status = function()
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
    vim.notify('[preview.nvim]: ' .. table.concat(parts, ', '), vim.log.levels.INFO)
  end,
}

---@param args string
local function dispatch(args)
  local subcmd = args ~= '' and args or 'toggle'
  local handler = handlers[subcmd]
  if handler then
    handler()
  else
    vim.notify('[preview.nvim]: unknown subcommand: ' .. subcmd, vim.log.levels.ERROR)
  end
end

---@param lead string
---@return string[]
local function complete(lead)
  return vim.tbl_filter(function(s)
    return s:find(lead, 1, true) == 1
  end, vim.tbl_keys(handlers))
end

function M.setup()
  vim.api.nvim_create_user_command('Preview', function(opts)
    dispatch(opts.args)
  end, {
    nargs = '?',
    complete = function(lead)
      return complete(lead)
    end,
    desc = 'Toggle, compile, clean, open, or check status of document preview',
  })
end

return M
