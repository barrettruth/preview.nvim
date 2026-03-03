local M = {}

local diagnostic = require('preview.diagnostic')
local log = require('preview.log')

---@type table<integer, preview.Process>
local active = {}

---@type table<integer, integer>
local watching = {}

---@type table<integer, true>
local opened = {}

---@type table<integer, string>
local last_output = {}

local debounce_timers = {}

local DEBOUNCE_MS = 500

---@param val string[]|fun(ctx: preview.Context): string[]
---@param ctx preview.Context
---@return string[]
local function eval_list(val, ctx)
  if type(val) == 'function' then
    return val(ctx)
  end
  return val
end

---@param val string|fun(ctx: preview.Context): string
---@param ctx preview.Context
---@return string
local function eval_string(val, ctx)
  if type(val) == 'function' then
    return val(ctx)
  end
  return val
end

---@param provider preview.ProviderConfig
---@param ctx preview.Context
---@return string[]?
local function resolve_reload_cmd(provider, ctx)
  if type(provider.reload) == 'function' then
    return provider.reload(ctx)
  elseif type(provider.reload) == 'table' then
    return vim.list_extend({}, provider.reload)
  end
  return nil
end

---@param bufnr integer
---@param name string
---@param provider preview.ProviderConfig
---@param ctx preview.Context
function M.compile(bufnr, name, provider, ctx)
  if vim.bo[bufnr].modified then
    vim.cmd('silent! update')
  end

  if active[bufnr] then
    log.dbg('killing existing process for buffer %d before recompile', bufnr)
    M.stop(bufnr)
  end

  local output_file = ''
  if provider.output then
    output_file = eval_string(provider.output, ctx)
  end

  local resolved_ctx = vim.tbl_extend('force', ctx, { output = output_file })

  local cwd = ctx.root
  if provider.cwd then
    cwd = eval_string(provider.cwd, resolved_ctx)
  end

  if output_file ~= '' then
    last_output[bufnr] = output_file
  end

  local reload_cmd = resolve_reload_cmd(provider, resolved_ctx)

  if reload_cmd then
    log.dbg(
      'starting long-running process for buffer %d with provider "%s": %s',
      bufnr,
      name,
      table.concat(reload_cmd, ' ')
    )

    local obj
    obj = vim.system(
      reload_cmd,
      {
        cwd = cwd,
        env = provider.env,
      },
      vim.schedule_wrap(function(result)
        if active[bufnr] and active[bufnr].obj == obj then
          active[bufnr] = nil
        end
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end

        if result.code ~= 0 then
          log.dbg('long-running process failed for buffer %d (exit code %d)', bufnr, result.code)
          local errors_mode = provider.errors
          if errors_mode == nil then
            errors_mode = 'diagnostic'
          end
          if provider.error_parser and errors_mode then
            local output = (result.stdout or '') .. (result.stderr or '')
            if errors_mode == 'diagnostic' then
              diagnostic.set(bufnr, name, provider.error_parser, output, ctx)
            elseif errors_mode == 'quickfix' then
              local ok, diagnostics = pcall(provider.error_parser, output, ctx)
              if ok and diagnostics and #diagnostics > 0 then
                local items = {}
                for _, d in ipairs(diagnostics) do
                  table.insert(items, {
                    bufnr = bufnr,
                    lnum = d.lnum + 1,
                    col = d.col + 1,
                    text = d.message,
                    type = d.severity == vim.diagnostic.severity.WARN and 'W' or 'E',
                  })
                end
                vim.fn.setqflist(items, 'r')
                vim.cmd('copen')
              end
            end
          end
          vim.api.nvim_exec_autocmds('User', {
            pattern = 'PreviewCompileFailed',
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

    if provider.open and not opened[bufnr] and output_file ~= '' then
      if provider.open == true then
        vim.ui.open(output_file)
      elseif type(provider.open) == 'table' then
        local open_cmd = vim.list_extend({}, provider.open)
        table.insert(open_cmd, output_file)
        vim.system(open_cmd)
      end
      opened[bufnr] = true
    end

    active[bufnr] = { obj = obj, provider = name, output_file = output_file, is_reload = true }

    vim.api.nvim_create_autocmd('BufWipeout', {
      buffer = bufnr,
      once = true,
      callback = function()
        M.stop(bufnr)
        last_output[bufnr] = nil
      end,
    })

    vim.api.nvim_exec_autocmds('User', {
      pattern = 'PreviewCompileStarted',
      data = { bufnr = bufnr, provider = name },
    })
    return
  end

  local cmd = vim.list_extend({}, provider.cmd)
  if provider.args then
    vim.list_extend(cmd, eval_list(provider.args, resolved_ctx))
  end

  log.dbg('compiling buffer %d with provider "%s": %s', bufnr, name, table.concat(cmd, ' '))

  local obj
  obj = vim.system(
    cmd,
    {
      cwd = cwd,
      env = provider.env,
    },
    vim.schedule_wrap(function(result)
      if active[bufnr] and active[bufnr].obj == obj then
        active[bufnr] = nil
      end
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end

      local errors_mode = provider.errors
      if errors_mode == nil then
        errors_mode = 'diagnostic'
      end

      if result.code == 0 then
        log.dbg('compilation succeeded for buffer %d', bufnr)
        if errors_mode == 'diagnostic' then
          diagnostic.clear(bufnr)
        elseif errors_mode == 'quickfix' then
          vim.fn.setqflist({}, 'r')
        end
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'PreviewCompileSuccess',
          data = { bufnr = bufnr, provider = name, output = output_file },
        })
        if provider.reload == true and output_file:match('%.html$') then
          local r = require('preview.reload')
          r.start()
          r.inject(output_file)
          r.broadcast()
        end
        if provider.open and not opened[bufnr] and output_file ~= '' then
          if provider.open == true then
            vim.ui.open(output_file)
          elseif type(provider.open) == 'table' then
            local open_cmd = vim.list_extend({}, provider.open)
            table.insert(open_cmd, output_file)
            vim.system(open_cmd)
          end
          opened[bufnr] = true
        end
      else
        log.dbg('compilation failed for buffer %d (exit code %d)', bufnr, result.code)
        if provider.error_parser and errors_mode then
          local output = (result.stdout or '') .. (result.stderr or '')
          if errors_mode == 'diagnostic' then
            diagnostic.set(bufnr, name, provider.error_parser, output, ctx)
          elseif errors_mode == 'quickfix' then
            local ok, diagnostics = pcall(provider.error_parser, output, ctx)
            if ok and diagnostics and #diagnostics > 0 then
              local items = {}
              for _, d in ipairs(diagnostics) do
                table.insert(items, {
                  bufnr = bufnr,
                  lnum = d.lnum + 1,
                  col = d.col + 1,
                  text = d.message,
                  type = d.severity == vim.diagnostic.severity.WARN and 'W' or 'E',
                })
              end
              vim.fn.setqflist(items, 'r')
              vim.cmd('copen')
            end
          end
        end
        vim.api.nvim_exec_autocmds('User', {
          pattern = 'PreviewCompileFailed',
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
      last_output[bufnr] = nil
    end,
  })

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'PreviewCompileStarted',
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
  for bufnr, _ in pairs(watching) do
    M.unwatch(bufnr)
  end
  require('preview.reload').stop()
end

---@param bufnr integer
---@param name string
---@param provider preview.ProviderConfig
---@param ctx_builder fun(bufnr: integer): preview.Context
function M.toggle(bufnr, name, provider, ctx_builder)
  local is_longrunning = type(provider.reload) == 'table' or type(provider.reload) == 'function'

  if is_longrunning then
    if active[bufnr] then
      M.stop(bufnr)
      vim.notify('[preview.nvim]: watching stopped', vim.log.levels.INFO)
    else
      M.compile(bufnr, name, provider, ctx_builder(bufnr))
      vim.notify('[preview.nvim]: watching with "' .. name .. '"', vim.log.levels.INFO)
    end
    return
  end

  if watching[bufnr] then
    M.unwatch(bufnr)
    vim.notify('[preview.nvim]: watching stopped', vim.log.levels.INFO)
    return
  end

  local au_id = vim.api.nvim_create_autocmd('BufWritePost', {
    buffer = bufnr,
    callback = function()
      if debounce_timers[bufnr] then
        debounce_timers[bufnr]:stop()
      else
        debounce_timers[bufnr] = vim.uv.new_timer()
      end
      debounce_timers[bufnr]:start(
        DEBOUNCE_MS,
        0,
        vim.schedule_wrap(function()
          local ctx = ctx_builder(bufnr)
          M.compile(bufnr, name, provider, ctx)
        end)
      )
    end,
  })

  watching[bufnr] = au_id
  log.dbg('watching buffer %d with provider "%s"', bufnr, name)
  vim.notify('[preview.nvim]: watching with "' .. name .. '"', vim.log.levels.INFO)

  vim.api.nvim_create_autocmd('BufWipeout', {
    buffer = bufnr,
    once = true,
    callback = function()
      M.unwatch(bufnr)
      opened[bufnr] = nil
    end,
  })

  M.compile(bufnr, name, provider, ctx_builder(bufnr))
end

---@param bufnr integer
function M.unwatch(bufnr)
  local au_id = watching[bufnr]
  if not au_id then
    return
  end
  vim.api.nvim_del_autocmd(au_id)
  if debounce_timers[bufnr] then
    debounce_timers[bufnr]:stop()
    debounce_timers[bufnr]:close()
    debounce_timers[bufnr] = nil
  end
  watching[bufnr] = nil
  log.dbg('unwatched buffer %d', bufnr)
end

---@param bufnr integer
---@param name string
---@param provider preview.ProviderConfig
---@param ctx preview.Context
function M.clean(bufnr, name, provider, ctx)
  if not provider.clean then
    vim.notify('[preview.nvim] provider "' .. name .. '" has no clean command', vim.log.levels.WARN)
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
        vim.notify('[preview.nvim] clean complete', vim.log.levels.INFO)
      else
        log.dbg('clean failed for buffer %d (exit code %d)', bufnr, result.code)
        vim.notify('[preview.nvim] clean failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
      end
    end)
  )
end

---@param bufnr integer
---@return boolean
function M.open(bufnr)
  local output = last_output[bufnr]
  if not output then
    log.dbg('no last output file for buffer %d', bufnr)
    return false
  end
  vim.ui.open(output)
  return true
end

---@param bufnr integer
---@return preview.Status
function M.status(bufnr)
  local proc = active[bufnr]
  if proc then
    return {
      compiling = not proc.is_reload,
      watching = watching[bufnr] ~= nil or proc.is_reload == true,
      provider = proc.provider,
      output_file = proc.output_file,
    }
  end
  return { compiling = false, watching = watching[bufnr] ~= nil }
end

M._test = {
  active = active,
  watching = watching,
  opened = opened,
  last_output = last_output,
  debounce_timers = debounce_timers,
}

return M
