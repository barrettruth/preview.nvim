---@class preview.ProviderConfig
---@field ft? string
---@field cmd string[]
---@field args? string[]|fun(ctx: preview.Context): string[]
---@field cwd? string|fun(ctx: preview.Context): string
---@field env? table<string, string>
---@field output? string|fun(ctx: preview.Context): string
---@field error_parser? fun(output: string, ctx: preview.Context): preview.Diagnostic[]
---@field errors? false|'diagnostic'|'quickfix'
---@field clean? string[]|fun(ctx: preview.Context): string[]
---@field open? boolean|string[]
---@field reload? boolean|string[]|fun(ctx: preview.Context): string[]
---@field detach? boolean

---@class preview.Config
---@field debug boolean|string
---@field providers table<string, preview.ProviderConfig>

---@class preview.Context
---@field bufnr integer
---@field file string
---@field root string
---@field ft string
---@field output? string

---@class preview.Diagnostic
---@field lnum integer
---@field col integer
---@field message string
---@field severity? integer
---@field end_lnum? integer
---@field end_col? integer
---@field source? string

---@class preview.Process
---@field obj table
---@field provider string
---@field output_file string
---@field is_reload? boolean

---@class preview
---@field setup fun(opts?: table)
---@field compile fun(bufnr?: integer)
---@field stop fun(bufnr?: integer)
---@field clean fun(bufnr?: integer)
---@field toggle fun(bufnr?: integer)
---@field open fun(bufnr?: integer)
---@field status fun(bufnr?: integer): preview.Status
---@field statusline fun(bufnr?: integer): string
---@field get_config fun(): preview.Config
local M = {}

local compiler = require('preview.compiler')
local log = require('preview.log')

---@type preview.Config
local default_config = {
  debug = false,
  providers = {},
}

---@type preview.Config
local config = vim.deepcopy(default_config)

---@param opts? table
function M.setup(opts)
  opts = opts or {}
  vim.validate('preview.setup opts', opts, 'table')

  local presets = require('preview.presets')
  local providers = {}
  local debug = false

  for k, v in pairs(opts) do
    if k == 'debug' then
      vim.validate('preview.setup opts.debug', v, { 'boolean', 'string' })
      debug = v
    elseif type(k) ~= 'number' then
      local preset = presets[k]
      if preset then
        if v == true then
          providers[preset.ft] = preset
        elseif type(v) == 'table' then
          providers[preset.ft] = vim.tbl_deep_extend('force', preset, v)
        end
      elseif type(v) == 'table' then
        providers[k] = v
      end
    end
  end

  for ft, provider in pairs(providers) do
    local prefix = 'providers.' .. ft
    vim.validate(prefix .. '.cmd', provider.cmd, 'table')
    vim.validate(prefix .. '.cmd[1]', provider.cmd[1], 'string')
    vim.validate(prefix .. '.args', provider.args, { 'table', 'function' }, true)
    vim.validate(prefix .. '.cwd', provider.cwd, { 'string', 'function' }, true)
    vim.validate(prefix .. '.output', provider.output, { 'string', 'function' }, true)
    vim.validate(prefix .. '.error_parser', provider.error_parser, 'function', true)
    vim.validate(prefix .. '.errors', provider.errors, function(x)
      return x == nil or x == false or x == 'diagnostic' or x == 'quickfix'
    end, 'false, "diagnostic", or "quickfix"')
    vim.validate(prefix .. '.open', provider.open, { 'boolean', 'table' }, true)
    vim.validate(prefix .. '.reload', provider.reload, { 'boolean', 'table', 'function' }, true)
    vim.validate(prefix .. '.detach', provider.detach, 'boolean', true)
  end

  if providers['plantuml'] then
    vim.filetype.add({
      extension = { puml = 'plantuml', pu = 'plantuml' },
    })
  end

  config = vim.tbl_deep_extend('force', default_config, {
    debug = debug,
    providers = providers,
  })

  log.set_enabled(config.debug)
  log.dbg('initialized with %d providers', vim.tbl_count(config.providers))
end

---@return preview.Config
function M.get_config()
  return config
end

---@param bufnr? integer
---@return string?
function M.resolve_provider(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype
  if not config.providers[ft] then
    log.dbg('no provider configured for filetype: %s', ft)
    return nil
  end
  return ft
end

---@param bufnr? integer
---@return preview.Context
function M.build_context(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = vim.fs.root(bufnr, { '.git' }) or vim.fn.fnamemodify(file, ':h')
  return {
    bufnr = bufnr,
    file = file,
    root = root,
    ft = vim.bo[bufnr].filetype,
  }
end

---@param bufnr? integer
function M.compile(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(bufnr) == '' then
    vim.notify('[preview.nvim]: buffer has no file name', vim.log.levels.WARN)
    return
  end
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim]: no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local ctx = M.build_context(bufnr)
  local provider = config.providers[name]
  compiler.compile(bufnr, name, provider, ctx, { oneshot = true })
end

---@param bufnr? integer
function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  compiler.stop(bufnr)
end

---@param bufnr? integer
function M.clean(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(bufnr) == '' then
    vim.notify('[preview.nvim]: buffer has no file name', vim.log.levels.WARN)
    return
  end
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim]: no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local ctx = M.build_context(bufnr)
  local provider = config.providers[name]
  compiler.clean(bufnr, name, provider, ctx)
end

---@param bufnr? integer
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(bufnr) == '' then
    vim.notify('[preview.nvim]: buffer has no file name', vim.log.levels.WARN)
    return
  end
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim]: no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local provider = config.providers[name]
  compiler.toggle(bufnr, name, provider, M.build_context)
end

---@param bufnr? integer
function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.api.nvim_buf_get_name(bufnr) == '' then
    vim.notify('[preview.nvim]: buffer has no file name', vim.log.levels.WARN)
    return
  end
  local name = M.resolve_provider(bufnr)
  local open_config = name and config.providers[name] and config.providers[name].open
  if not compiler.open(bufnr, open_config) then
    vim.notify('[preview.nvim]: no output file available for this buffer', vim.log.levels.WARN)
  end
end

---@class preview.Status
---@field compiling boolean
---@field watching boolean
---@field provider? string
---@field output_file? string

---@param bufnr? integer
---@return preview.Status
function M.status(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return compiler.status(bufnr)
end

---@param bufnr? integer
---@return string
function M.statusline(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local s = compiler.status(bufnr)
  if s.compiling then
    return 'compiling'
  elseif s.watching then
    return 'watching'
  end
  return ''
end

M._test = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  reset = function()
    config = vim.deepcopy(default_config)
  end,
}

if vim.g.preview then
  M.setup(vim.g.preview)
end

return M
