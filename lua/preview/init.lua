---@class preview.ProviderConfig
---@field cmd string[]
---@field args? string[]|fun(ctx: preview.Context): string[]
---@field cwd? string|fun(ctx: preview.Context): string
---@field env? table<string, string>
---@field output? string|fun(ctx: preview.Context): string
---@field error_parser? fun(stderr: string, ctx: preview.Context): preview.Diagnostic[]
---@field clean? string[]|fun(ctx: preview.Context): string[]

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
---@field compile fun(bufnr?: integer)
---@field stop fun(bufnr?: integer)
---@field clean fun(bufnr?: integer)
---@field watch fun(bufnr?: integer)
---@field status fun(bufnr?: integer): preview.Status
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

local initialized = false

local function init()
  if initialized then
    return
  end
  initialized = true

  local opts = vim.g.preview or {}

  vim.validate('preview config', opts, 'table')
  if opts.debug ~= nil then
    vim.validate('preview config.debug', opts.debug, { 'boolean', 'string' })
  end
  if opts.providers ~= nil then
    vim.validate('preview config.providers', opts.providers, 'table')
  end

  config = vim.tbl_deep_extend('force', default_config, opts)
  log.set_enabled(config.debug)
  log.dbg('initialized with %d providers', vim.tbl_count(config.providers))
end

---@return preview.Config
function M.get_config()
  init()
  return config
end

---@param bufnr? integer
---@return string?
function M.resolve_provider(bufnr)
  init()
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
  init()
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
  init()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim] no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local provider = config.providers[name]
  local ctx = M.build_context(bufnr)
  compiler.compile(bufnr, name, provider, ctx)
end

---@param bufnr? integer
function M.stop(bufnr)
  init()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  compiler.stop(bufnr)
end

---@param bufnr? integer
function M.clean(bufnr)
  init()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim] no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local provider = config.providers[name]
  local ctx = M.build_context(bufnr)
  compiler.clean(bufnr, name, provider, ctx)
end

---@param bufnr? integer
function M.watch(bufnr)
  init()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = M.resolve_provider(bufnr)
  if not name then
    vim.notify('[preview.nvim] no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local provider = config.providers[name]
  compiler.watch(bufnr, name, provider, M.build_context)
end

---@class preview.Status
---@field compiling boolean
---@field watching boolean
---@field provider? string
---@field output_file? string

---@param bufnr? integer
---@return preview.Status
function M.status(bufnr)
  init()
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return compiler.status(bufnr)
end

M._test = {
  ---@diagnostic disable-next-line: assign-type-mismatch
  reset = function()
    initialized = false
    config = vim.deepcopy(default_config)
  end,
}

return M
