local M = {}

local diagnostic = require('preview.diagnostic')
local log = require('preview.log')

---@class preview.BufState
---@field watching boolean
---@field process? table
---@field is_reload? boolean
---@field provider? string
---@field output? string
---@field viewer? table
---@field viewer_open? boolean
---@field open_watcher? uv.uv_fs_event_t
---@field output_watcher? uv.uv_fs_event_t
---@field has_errors? boolean
---@field debounce? uv.uv_timer_t
---@field bwp_autocmd? integer
---@field unload_autocmd? integer

---@type table<integer, preview.BufState>
local state = {}

local DEBOUNCE_MS = 500

---@param bufnr integer
---@return preview.BufState
local function get_state(bufnr)
  if not state[bufnr] then
    state[bufnr] = { watching = false }
  end
  return state[bufnr]
end

---@param bufnr integer
local function stop_open_watcher(bufnr)
  local s = state[bufnr]
  if not (s and s.open_watcher) then
    return
  end
  s.open_watcher:stop()
  s.open_watcher:close()
  s.open_watcher = nil
end

---@param bufnr integer
local function stop_output_watcher(bufnr)
  local s = state[bufnr]
  if not (s and s.output_watcher) then
    return
  end
  s.output_watcher:stop()
  s.output_watcher:close()
  s.output_watcher = nil
end

---@param bufnr integer
local function close_viewer(bufnr)
  local s = state[bufnr]
  if not (s and s.viewer) then
    return
  end
  s.viewer:kill('sigterm')
  s.viewer = nil
end

---@param bufnr integer
---@param name string
---@param provider preview.ProviderConfig
---@param ctx preview.Context
---@param output string
---@return integer
local function handle_errors(bufnr, name, provider, ctx, output)
  local errors_mode = provider.errors
  if errors_mode == nil then
    errors_mode = 'diagnostic'
  end
  if not (provider.error_parser and errors_mode) then
    return 0
  end
  if errors_mode == 'diagnostic' then
    return diagnostic.set(bufnr, name, provider.error_parser, output, ctx)
  elseif errors_mode == 'quickfix' then
    local ok, diags = pcall(provider.error_parser, output, ctx)
    if ok and diags and #diags > 0 then
      local items = {}
      for _, d in ipairs(diags) do
        table.insert(items, {
          bufnr = bufnr,
          lnum = d.lnum + 1,
          col = d.col + 1,
          text = d.message,
          type = d.severity == vim.diagnostic.severity.WARN and 'W' or 'E',
        })
      end
      vim.fn.setqflist(items, 'r')
      local win = vim.fn.win_getid()
      vim.cmd.cwindow()
      vim.fn.win_gotoid(win)
      return #diags
    end
  end
  return 0
end

---@param bufnr integer
---@param provider preview.ProviderConfig
local function clear_errors(bufnr, provider)
  local errors_mode = provider.errors
  if errors_mode == nil then
    errors_mode = 'diagnostic'
  end
  if errors_mode == 'diagnostic' then
    diagnostic.clear(bufnr)
  elseif errors_mode == 'quickfix' then
    vim.fn.setqflist({}, 'r')
    vim.cmd.cwindow()
  end
end

---@param bufnr integer
---@param output_file string
---@param open_config boolean|string[]
local function do_open(bufnr, output_file, open_config)
  if open_config == true then
    vim.ui.open(output_file)
  elseif type(open_config) == 'table' then
    local open_cmd = vim.list_extend({}, open_config)
    table.insert(open_cmd, output_file)
    log.dbg('opening viewer for buffer %d: %s', bufnr, table.concat(open_cmd, ' '))
    local proc
    proc = vim.system(
      open_cmd,
      {},
      vim.schedule_wrap(function()
        local s = state[bufnr]
        if s and s.viewer == proc then
          log.dbg('viewer exited for buffer %d, resetting viewer_open', bufnr)
          s.viewer = nil
          s.viewer_open = nil
        else
          log.dbg('viewer exited for buffer %d (stale proc, ignoring)', bufnr)
        end
      end)
    )
    get_state(bufnr).viewer = proc
  end
end

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
---@param s preview.BufState
local function stop_watching(bufnr, s)
  s.watching = false
  M.stop(bufnr)
  stop_open_watcher(bufnr)
  stop_output_watcher(bufnr)
  close_viewer(bufnr)
  s.viewer_open = nil
  if s.bwp_autocmd then
    vim.api.nvim_del_autocmd(s.bwp_autocmd)
    s.bwp_autocmd = nil
  end
  if s.debounce then
    s.debounce:stop()
    s.debounce:close()
    s.debounce = nil
  end
end

---@param bufnr integer
---@param name string
---@param provider preview.ProviderConfig
---@param ctx preview.Context
---@param opts? {oneshot?: boolean}
function M.compile(bufnr, name, provider, ctx, opts)
  opts = opts or {}

  if vim.fn.executable(provider.cmd[1]) ~= 1 then
    vim.notify(
      '[preview.nvim]: "' .. provider.cmd[1] .. '" is not executable (run :checkhealth preview)',
      vim.log.levels.ERROR
    )
    return
  end

  if vim.bo[bufnr].modified then
    vim.cmd('silent! update')
  end

  local s = get_state(bufnr)

  if s.process then
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
    s.output = output_file
  end

  local reload_cmd
  if not opts.oneshot then
    reload_cmd = resolve_reload_cmd(provider, resolved_ctx)
  end

  if reload_cmd then
    log.dbg(
      'starting long-running process for buffer %d with provider "%s": %s',
      bufnr,
      name,
      table.concat(reload_cmd, ' ')
    )

    local stderr_acc = {}
    local obj
    obj = vim.system(
      reload_cmd,
      {
        cwd = cwd,
        env = provider.env,
        stderr = vim.schedule_wrap(function(_err, data)
          if not data or not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          stderr_acc[#stderr_acc + 1] = data
          local count = handle_errors(bufnr, name, provider, ctx, table.concat(stderr_acc))
          if count > 0 and not s.has_errors then
            s.has_errors = true
            vim.notify('[preview.nvim]: compilation failed', vim.log.levels.ERROR)
          end
        end),
      },
      vim.schedule_wrap(function(result)
        local cs = state[bufnr]
        if cs and cs.process == obj then
          cs.process = nil
        end
        if not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        if result.code ~= 0 then
          log.dbg('long-running process failed for buffer %d (exit code %d)', bufnr, result.code)
          vim.notify('[preview.nvim]: compilation failed', vim.log.levels.ERROR)
          handle_errors(bufnr, name, provider, ctx, (result.stdout or '') .. (result.stderr or ''))
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

    if provider.open and not opts.oneshot and not s.viewer_open and output_file ~= '' then
      local pre_stat = vim.uv.fs_stat(output_file)
      local pre_mtime = pre_stat and pre_stat.mtime.sec or 0
      local out_dir = vim.fn.fnamemodify(output_file, ':h')
      local out_name = vim.fn.fnamemodify(output_file, ':t')
      stop_open_watcher(bufnr)
      local watcher = vim.uv.new_fs_event()
      if watcher then
        s.open_watcher = watcher
        watcher:start(
          out_dir,
          {},
          vim.schedule_wrap(function(err, filename, _events)
            if err or vim.fn.fnamemodify(filename or '', ':t') ~= out_name then
              return
            end
            local cs = state[bufnr]
            if not cs then
              return
            end
            if cs.viewer_open then
              log.dbg('watcher fired for buffer %d but viewer already open', bufnr)
              return
            end
            if not vim.api.nvim_buf_is_valid(bufnr) then
              stop_open_watcher(bufnr)
              return
            end
            local new_stat = vim.uv.fs_stat(output_file)
            if not (new_stat and new_stat.mtime.sec > pre_mtime) then
              log.dbg(
                'watcher fired for buffer %d but mtime not newer (%d <= %d)',
                bufnr,
                new_stat and new_stat.mtime.sec or 0,
                pre_mtime
              )
              return
            end
            log.dbg('watcher opening viewer for buffer %d', bufnr)
            cs.viewer_open = true
            stderr_acc = {}
            clear_errors(bufnr, provider)
            do_open(bufnr, output_file, provider.open)
          end)
        )
      end
    end

    if output_file ~= '' then
      local out_dir = vim.fn.fnamemodify(output_file, ':h')
      local out_name = vim.fn.fnamemodify(output_file, ':t')
      stop_output_watcher(bufnr)
      local ow = vim.uv.new_fs_event()
      if ow then
        s.output_watcher = ow
        local last_mtime = 0
        local stat = vim.uv.fs_stat(output_file)
        if stat then
          last_mtime = stat.mtime.sec
        end
        ow:start(
          out_dir,
          {},
          vim.schedule_wrap(function(err, filename, _events)
            if err or vim.fn.fnamemodify(filename or '', ':t') ~= out_name then
              return
            end
            if not vim.api.nvim_buf_is_valid(bufnr) then
              stop_output_watcher(bufnr)
              return
            end
            local new_stat = vim.uv.fs_stat(output_file)
            if not (new_stat and new_stat.mtime.sec > last_mtime) then
              return
            end
            last_mtime = new_stat.mtime.sec
            log.dbg('output updated for buffer %d', bufnr)
            vim.notify('[preview.nvim]: compilation complete', vim.log.levels.INFO)
            stderr_acc = {}
            s.has_errors = false
            clear_errors(bufnr, provider)
            vim.api.nvim_exec_autocmds('User', {
              pattern = 'PreviewCompileSuccess',
              data = { bufnr = bufnr, provider = name, output = output_file },
            })
          end)
        )
      end
    end

    s.process = obj
    s.provider = name
    s.is_reload = true
    s.has_errors = false

    vim.notify('[preview.nvim]: compiling...', vim.log.levels.INFO)
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
  if provider.extra_args then
    vim.list_extend(cmd, eval_list(provider.extra_args, resolved_ctx))
  end

  log.dbg('compiling buffer %d with provider "%s": %s', bufnr, name, table.concat(cmd, ' '))

  local obj
  obj = vim.system(
    cmd,
    { cwd = cwd, env = provider.env },
    vim.schedule_wrap(function(result)
      local cs = state[bufnr]
      if cs and cs.process == obj then
        cs.process = nil
      end
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      if result.code == 0 then
        log.dbg('compilation succeeded for buffer %d', bufnr)
        vim.notify('[preview.nvim]: compilation complete', vim.log.levels.INFO)
        clear_errors(bufnr, provider)
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
        cs = state[bufnr]
        if
          provider.open
          and not opts.oneshot
          and cs
          and not cs.viewer_open
          and output_file ~= ''
          and vim.uv.fs_stat(output_file)
        then
          cs.viewer_open = true
          do_open(bufnr, output_file, provider.open)
        end
      else
        log.dbg('compilation failed for buffer %d (exit code %d)', bufnr, result.code)
        vim.notify('[preview.nvim]: compilation failed', vim.log.levels.ERROR)
        handle_errors(bufnr, name, provider, ctx, (result.stdout or '') .. (result.stderr or ''))
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

  s.process = obj
  s.provider = name
  s.is_reload = false

  vim.notify('[preview.nvim]: compiling...', vim.log.levels.INFO)
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'PreviewCompileStarted',
    data = { bufnr = bufnr, provider = name },
  })
end

---@param bufnr integer
function M.stop(bufnr)
  local s = state[bufnr]
  if not s then
    return
  end
  stop_output_watcher(bufnr)
  local obj = s.process
  if not obj then
    return
  end
  log.dbg('stopping process for buffer %d', bufnr)
  obj:kill('sigterm')

  local timer = vim.uv.new_timer()
  if timer then
    timer:start(5000, 0, function()
      timer:close()
      local cs = state[bufnr]
      if cs and cs.process == obj then
        obj:kill('sigkill')
        cs.process = nil
      end
    end)
  end
end

function M.stop_all()
  for bufnr, s in pairs(state) do
    stop_watching(bufnr, s)
    if s.unload_autocmd then
      vim.api.nvim_del_autocmd(s.unload_autocmd)
    end
    state[bufnr] = nil
  end
  require('preview.reload').stop()
end

---@param bufnr integer
---@param name string
---@param provider preview.ProviderConfig
---@param ctx_builder fun(bufnr: integer): preview.Context
function M.toggle(bufnr, name, provider, ctx_builder)
  local is_longrunning = type(provider.reload) == 'table' or type(provider.reload) == 'function'
  local s = get_state(bufnr)

  if s.watching then
    local output = s.output
    if not s.viewer_open and provider.open and output and vim.uv.fs_stat(output) then
      log.dbg('toggle reopen viewer for buffer %d', bufnr)
      s.viewer_open = true
      do_open(bufnr, output, provider.open)
    else
      log.dbg('toggle off for buffer %d', bufnr)
      stop_watching(bufnr, s)
      vim.notify('[preview.nvim]: watching stopped', vim.log.levels.INFO)
    end
    return
  end

  log.dbg('toggle on for buffer %d', bufnr)
  s.watching = true

  if s.unload_autocmd then
    vim.api.nvim_del_autocmd(s.unload_autocmd)
  end
  s.unload_autocmd = vim.api.nvim_create_autocmd('BufUnload', {
    buffer = bufnr,
    once = true,
    callback = function()
      M.stop(bufnr)
      stop_open_watcher(bufnr)
      stop_output_watcher(bufnr)
      if not provider.detach then
        close_viewer(bufnr)
      end
      state[bufnr] = nil
    end,
  })

  if not is_longrunning then
    s.bwp_autocmd = vim.api.nvim_create_autocmd('BufWritePost', {
      buffer = bufnr,
      callback = function()
        local ds = state[bufnr]
        if not ds then
          return
        end
        if ds.debounce then
          ds.debounce:stop()
        else
          ds.debounce = vim.uv.new_timer()
        end
        ds.debounce:start(
          DEBOUNCE_MS,
          0,
          vim.schedule_wrap(function()
            M.compile(bufnr, name, provider, ctx_builder(bufnr))
          end)
        )
      end,
    })
    log.dbg('watching buffer %d with provider "%s"', bufnr, name)
  end

  M.compile(bufnr, name, provider, ctx_builder(bufnr))
end

---@param bufnr integer
function M.unwatch(bufnr)
  local s = state[bufnr]
  if not s then
    return
  end
  stop_watching(bufnr, s)
  log.dbg('unwatched buffer %d', bufnr)
end

---@param bufnr integer
---@param name string
---@param provider preview.ProviderConfig
---@param ctx preview.Context
function M.clean(bufnr, name, provider, ctx)
  if not provider.clean then
    vim.notify(
      '[preview.nvim]: provider "' .. name .. '" has no clean command',
      vim.log.levels.WARN
    )
    return
  end

  local output_file = ''
  if provider.output then
    output_file = eval_string(provider.output, ctx)
  end
  local resolved_ctx = vim.tbl_extend('force', ctx, { output = output_file })

  local cmd = eval_list(provider.clean, resolved_ctx)
  local cwd = resolved_ctx.root
  if provider.cwd then
    cwd = eval_string(provider.cwd, resolved_ctx)
  end

  log.dbg('cleaning buffer %d with provider "%s": %s', bufnr, name, table.concat(cmd, ' '))

  vim.system(
    cmd,
    { cwd = cwd },
    vim.schedule_wrap(function(result)
      if result.code == 0 then
        log.dbg('clean succeeded for buffer %d', bufnr)
        vim.notify('[preview.nvim]: clean complete', vim.log.levels.INFO)
      else
        log.dbg('clean failed for buffer %d (exit code %d)', bufnr, result.code)
        vim.notify('[preview.nvim]: clean failed: ' .. (result.stderr or ''), vim.log.levels.ERROR)
      end
    end)
  )
end

---@param bufnr integer
---@return boolean
function M.open(bufnr, open_config)
  local s = state[bufnr]
  local output = s and s.output
  if not output then
    log.dbg('no last output file for buffer %d', bufnr)
    return false
  end
  if not vim.uv.fs_stat(output) then
    log.dbg('output file no longer exists for buffer %d: %s', bufnr, output)
    return false
  end
  do_open(bufnr, output, open_config)
  return true
end

---@param bufnr integer
---@return preview.Status
function M.status(bufnr)
  local s = state[bufnr]
  if not s then
    return { compiling = false, watching = false }
  end
  return {
    compiling = s.process ~= nil and not s.is_reload,
    watching = s.watching,
    provider = s.provider,
    output_file = s.output,
  }
end

M._test = {
  state = state,
}

return M
