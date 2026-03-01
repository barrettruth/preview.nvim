local M = {}

local diagnostic = require('render.diagnostic')
local log = require('render.log')

---@type table<integer, render.Process>
local active = {}

---@param val string[]|fun(ctx: render.Context): string[]
---@param ctx render.Context
---@return string[]
local function eval_list(val, ctx)
  if type(val) == 'function' then
    return val(ctx)
  end
  return val
end

---@param val string|fun(ctx: render.Context): string
---@param ctx render.Context
---@return string
local function eval_string(val, ctx)
  if type(val) == 'function' then
    return val(ctx)
  end
  return val
end

---@param bufnr integer
---@param name string
---@param provider render.ProviderConfig
---@param ctx render.Context
function M.compile(bufnr, name, provider, ctx)
  if vim.bo[bufnr].modified then
    vim.cmd('silent! update')
  end

  if active[bufnr] then
    log.dbg('killing existing process for buffer %d before recompile', bufnr)
    M.stop(bufnr)
  end

  local cmd = vim.list_extend({}, provider.cmd)
  if provider.args then
    vim.list_extend(cmd, eval_list(provider.args, ctx))
  end

  local cwd = ctx.root
  if provider.cwd then
    cwd = eval_string(provider.cwd, ctx)
  end

  local output_file = ''
  if provider.output then
    output_file = eval_string(provider.output, ctx)
  end

  log.dbg('compiling buffer %d with provider "%s": %s', bufnr, name, table.concat(cmd, ' '))

  local obj = vim.system(
    cmd,
    {
      cwd = cwd,
      env = provider.env,
    },
    vim.schedule_wrap(function(result)
      active[bufnr] = nil

      if result.code == 0 then
        log.dbg('compilation succeeded for buffer %d', bufnr)
        diagnostic.clear(bufnr)
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'RenderCompileSuccess',
          data = { bufnr = bufnr, provider = name, output = output_file },
        })
      else
        log.dbg('compilation failed for buffer %d (exit code %d)', bufnr, result.code)
        if provider.error_parser then
          diagnostic.set(bufnr, name, provider.error_parser, result.stderr or '', ctx)
        end
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'RenderCompileFailed',
          data = {
            bufnr = bufnr,
            provider = name,
            code = result.code,
            stderr = result.stderr or '',
          },
        })
      end
    end)
  )

  active[bufnr] = { obj = obj, provider = name, output_file = output_file }

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = bufnr,
    once = true,
    callback = function()
      M.stop(bufnr)
    end,
  })

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'RenderCompileStarted',
    data = { bufnr = bufnr, provider = name },
  })
end

---@param bufnr integer
function M.stop(bufnr)
  local proc = active[bufnr]
  if not proc then
    return
  end
  log.dbg('stopping process for buffer %d', bufnr)
  ---@type fun(self: table, signal: string|integer)
  local kill = proc.obj.kill
  kill(proc.obj, 'sigterm')

  local timer = vim.uv.new_timer()
  if timer then
    timer:start(5000, 0, function()
      timer:close()
      if active[bufnr] and active[bufnr].obj == proc.obj then
        kill(proc.obj, 'sigkill')
        active[bufnr] = nil
      end
    end)
  end
end

function M.stop_all()
  for bufnr, _ in pairs(active) do
    M.stop(bufnr)
  end
end

---@param bufnr integer
---@param name string
---@param provider render.ProviderConfig
---@param ctx render.Context
function M.clean(bufnr, name, provider, ctx)
  if not provider.clean then
    vim.notify('[render.nvim] provider "' .. name .. '" has no clean command', vim.log.levels.WARN)
    return
  end

  local cmd = eval_list(provider.clean, ctx)
  local cwd = ctx.root
  if provider.cwd then
    cwd = eval_string(provider.cwd, ctx)
  end

  log.dbg('cleaning buffer %d with provider "%s": %s', bufnr, name, table.concat(cmd, ' '))

  vim.system(
    cmd,
    { cwd = cwd },
    vim.schedule_wrap(function(result)
      if result.code == 0 then
        log.dbg('clean succeeded for buffer %d', bufnr)
        vim.notify('[render.nvim] clean complete', vim.log.levels.INFO)
      else
        log.dbg('clean failed for buffer %d (exit code %d)', bufnr, result.code)
        vim.notify('[render.nvim] clean failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
      end
    end)
  )
end

---@param bufnr integer
---@return render.Status
function M.status(bufnr)
  local proc = active[bufnr]
  if proc then
    return { compiling = true, provider = proc.provider, output_file = proc.output_file }
  end
  return { compiling = false }
end

M._test = {
  active = active,
}

return M
