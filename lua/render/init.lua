---@class render.ProviderConfig
---@field cmd string[]
---@field args? string[]|fun(ctx: render.Context): string[]
---@field cwd? string|fun(ctx: render.Context): string
---@field env? table<string, string>
---@field output? string|fun(ctx: render.Context): string
---@field error_parser? fun(stderr: string, ctx: render.Context): vim.Diagnostic[]
---@field clean? string[]|fun(ctx: render.Context): string[]

---@class render.Config
---@field debug boolean|string
---@field providers table<string, render.ProviderConfig>
---@field providers_by_ft table<string, string>

---@class render.Context
---@field bufnr integer
---@field file string
---@field root string
---@field ft string

---@class render.Process
---@field obj vim.SystemObj
---@field provider string
---@field output_file string

---@class render
---@field compile fun(bufnr?: integer)
---@field stop fun(bufnr?: integer)
---@field clean fun(bufnr?: integer)
---@field status fun(bufnr?: integer): render.Status
---@field get_config fun(): render.Config
local M = {}

local compiler = require('render.compiler')
local log = require('render.log')

---@type render.Config
local default_config = {
  debug = false,
  providers = {},
  providers_by_ft = {},
}

---@type render.Config
local config = vim.deepcopy(default_config)

local initialized = false

local function init()
  if initialized then
    return
  end
  initialized = true

  local opts = vim.g.render or {}

  vim.validate('render config', opts, 'table')
  if opts.debug ~= nil then
    vim.validate('render config.debug', opts.debug, { 'boolean', 'string' })
  end
  if opts.providers ~= nil then
    vim.validate('render config.providers', opts.providers, 'table')
  end
  if opts.providers_by_ft ~= nil then
    vim.validate('render config.providers_by_ft', opts.providers_by_ft, 'table')
  end

  config = vim.tbl_deep_extend('force', default_config, opts)
  log.set_enabled(config.debug)
  log.dbg('initialized with %d providers', vim.tbl_count(config.providers))
end

---@return render.Config
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
  local name = config.providers_by_ft[ft]
  if not name then
    log.dbg('no provider mapped for filetype: %s', ft)
    return nil
  end
  if not config.providers[name] then
    log.dbg('provider "%s" mapped for ft "%s" but not configured', name, ft)
    return nil
  end
  return name
end

---@param bufnr? integer
---@return render.Context
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
    vim.notify('[render.nvim] no provider configured for this filetype', vim.log.levels.WARN)
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
    vim.notify('[render.nvim] no provider configured for this filetype', vim.log.levels.WARN)
    return
  end
  local provider = config.providers[name]
  local ctx = M.build_context(bufnr)
  compiler.clean(bufnr, name, provider, ctx)
end

---@class render.Status
---@field compiling boolean
---@field provider? string
---@field output_file? string

---@param bufnr? integer
---@return render.Status
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
