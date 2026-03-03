---@class preview.ProviderConfig
---@field ft? string
---@field cmd string[]
---@field args? string[]|fun(ctx: preview.Context): string[]
---@field cwd? string|fun(ctx: preview.Context): string
---@field env? table<string, string>
---@field output? string|fun(ctx: preview.Context): string
---@field error_parser? fun(stderr: string, ctx: preview.Context): preview.Diagnostic[]
---@field clean? string[]|fun(ctx: preview.Context): string[]
---@field open? boolean|string[]

---@class preview.Config
---@field debug boolean|string
---@field providers table<string, preview.ProviderConfig>

---@class preview.Context
---@field bufnr integer
---@field file string
---@field root string
---@field ft string

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

---@class preview
---@field setup fun(opts?: table)
---@field compile fun(bufnr?: integer)
---@field stop fun(bufnr?: integer)
---@field clean fun(bufnr?: integer)
---@field toggle fun(bufnr?: integer)
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
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim] no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local ctx = M.build_context(bufnr)
  local provider = config.providers[name]
  compiler.compile(bufnr, name, provider, ctx)
end

---@param bufnr? integer
function M.stop(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  compiler.stop(bufnr)
end

---@param bufnr? integer
function M.clean(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim] no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local ctx = M.build_context(bufnr)
  local provider = config.providers[name]
  compiler.clean(bufnr, name, provider, ctx)
end

---@param bufnr? integer
function M.toggle(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim] no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local provider = config.providers[name]
  compiler.toggle(bufnr, name, provider, M.build_context)
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

return M
