local M = {}

---@param output string
---@return preview.Diagnostic[]
local function parse_typst(output)
  local diagnostics = {}
  for line in output:gmatch('[^\r\n]+') do
    local _, lnum, col, severity, msg = line:match('^(.+):(%d+):(%d+): (%w+): (.+)$')
    if lnum then
      local sev = vim.diagnostic.severity.ERROR
      if severity == 'warning' then
        sev = vim.diagnostic.severity.WARN
      end
      table.insert(diagnostics, {
        lnum = tonumber(lnum) - 1,
        col = tonumber(col) - 1,
        message = msg,
        severity = sev,
      })
    end
  end
  return diagnostics
end

---@param output string
---@return string?
local function summarize_typst(output)
  local diagnostics = parse_typst(output)
  for _, diagnostic in ipairs(diagnostics) do
    if diagnostic.severity == vim.diagnostic.severity.ERROR then
      return diagnostic.message
    end
  end
end

---@param output string
---@return preview.Diagnostic[]
local function parse_latexmk(output)
  local diagnostics = {}
  for line in output:gmatch('[^\r\n]+') do
    local _, lnum, msg = line:match('^%.?/?(.+%.tex):(%d+): (.+)$')
    if lnum then
      table.insert(diagnostics, {
        lnum = tonumber(lnum) - 1,
        col = 0,
        message = msg,
        severity = vim.diagnostic.severity.ERROR,
      })
    else
      local rule_msg = line:match('^%s+(%S.+gave return code %d+)$')
      if rule_msg then
        table.insert(diagnostics, {
          lnum = 0,
          col = 0,
          message = rule_msg,
          severity = vim.diagnostic.severity.ERROR,
        })
      end
    end
  end
  return diagnostics
end

---@param output string
---@return string?
local function summarize_latexmk(output)
  for line in output:gmatch('[^\r\n]+') do
    local fpath, lnum, msg = line:match('^%.?/?(.+%.tex):(%d+):%s*(.+)$')
    if fpath and msg and not msg:match('^%s*==>') then
      local fname = fpath:match('([^/]+)$') or fpath
      return string.format('%s:%s: %s', fname, lnum, msg)
    end
    local bang = line:match('^!%s+(.+)$')
    if bang and not bang:match('^%s*==>') then
      return bang
    end
  end
end

---@param msg string?
---@return string?
local function normalize_pdflatex_message(msg)
  if type(msg) ~= 'string' then
    return nil
  end
  msg = msg:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if msg == '' then
    return nil
  end
  return msg
end

---@param msg string?
---@return boolean
local function is_pdflatex_noise(msg)
  msg = normalize_pdflatex_message(msg)
  if not msg then
    return true
  end
  return msg == 'Emergency stop.'
    or msg:match('^==>%s*Fatal error occurred, no output PDF file produced!?$') ~= nil
end

---@param output string
---@return string?
local function summarize_pdflatex(output)
  for line in output:gmatch('[^\r\n]+') do
    local msg = normalize_pdflatex_message(line:match('^!%s+(LaTeX Error: .+)$'))
    if msg then
      return msg
    end
  end
  for line in output:gmatch('[^\r\n]+') do
    local _, _, msg = line:match('^%.?/?(.+%.tex):(%d+):%s*(.+)$')
    msg = normalize_pdflatex_message(msg)
    if msg and not is_pdflatex_noise(msg) then
      return msg
    end
  end
  for line in output:gmatch('[^\r\n]+') do
    local msg = normalize_pdflatex_message(line:match('^!%s+(.+)$'))
    if msg and not is_pdflatex_noise(msg) then
      return msg
    end
  end
end

---@param msg string?
---@return string?
local function normalize_tectonic_message(msg)
  if type(msg) ~= 'string' then
    return nil
  end
  msg = msg:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if msg == '' then
    return nil
  end
  local prefix, body = msg:match('^(.-:%d+:%s*)!%s*(.+)$')
  if prefix and body then
    return prefix .. body
  end
  msg = msg:gsub('^!%s*', '')
  return msg
end

---@param result preview.Result
---@return string?
local function summarize_tectonic(result)
  local stderr = result.stderr ~= '' and result.stderr or result.output or ''
  for line in stderr:gmatch('[^\r\n]+') do
    local msg = normalize_tectonic_message(line:match('^error:%s*(.+)$'))
    if
      msg
      and msg ~= 'halted on potentially-recoverable error as specified'
      and not msg:match('^%*%*%*%s')
    then
      return msg
    end
  end
end

---@param output string
---@return preview.Diagnostic[]
local function parse_pandoc(output)
  local diagnostics = {}
  local lines = vim.split(output, '\n')
  local i = 1
  while i <= #lines do
    local line = lines[i]
    local lnum, col, msg = line:match('%(line (%d+), column (%d+)%):%s*(.*)$')
    if lnum then
      if msg == '' then
        for j = i + 1, math.min(i + 2, #lines) do
          local next_line = lines[j]:match('^%s*(.+)$')
          if next_line and not next_line:match('^YAML parse exception') then
            msg = next_line
            break
          end
        end
      end
      if msg ~= '' then
        table.insert(diagnostics, {
          lnum = tonumber(lnum) - 1,
          col = tonumber(col) - 1,
          message = msg,
          severity = vim.diagnostic.severity.ERROR,
        })
      end
    else
      local errmsg = line:match('^pandoc: (.+)$')
      if errmsg then
        table.insert(diagnostics, {
          lnum = 0,
          col = 0,
          message = errmsg,
          severity = vim.diagnostic.severity.ERROR,
        })
      end
    end
    i = i + 1
  end
  return diagnostics
end

---@param output string
---@return preview.Diagnostic[]
local function parse_asciidoctor(output)
  local diagnostics = {}
  for line in output:gmatch('[^\r\n]+') do
    local severity, _, lnum, msg = line:match('^asciidoctor: (%u+): (.+): line (%d+): (.+)$')
    if lnum then
      local sev = vim.diagnostic.severity.ERROR
      if severity == 'WARNING' then
        sev = vim.diagnostic.severity.WARN
      end
      table.insert(diagnostics, {
        lnum = tonumber(lnum) - 1,
        col = 0,
        message = msg,
        severity = sev,
      })
    end
  end
  return diagnostics
end

---@param output string
---@return preview.Diagnostic[]
local function parse_mermaid(output)
  local lnum = output:match('Parse error on line (%d+)')
  if not lnum then
    return {}
  end
  local msg = output:match('(Expecting .+)') or 'parse error'
  return {
    {
      lnum = tonumber(lnum) - 1,
      col = 0,
      message = msg,
      severity = vim.diagnostic.severity.ERROR,
    },
  }
end

---@param output string
---@return preview.Diagnostic[]
local function parse_quarto(output)
  output = output:gsub('\27%[[0-9;]*m', '')
  local diagnostics = parse_pandoc(output)
  if #diagnostics > 0 then
    return diagnostics
  end
  local msg, lnum, col = output:match('ERROR:%s*([^\r\n]-)%s*%((%d+):(%d+)%)')
  if msg then
    return {
      {
        lnum = tonumber(lnum) - 1,
        col = tonumber(col) - 1,
        message = msg,
        severity = vim.diagnostic.severity.ERROR,
      },
    }
  end
  msg = output:match('ERROR:%s*([^\r\n]+)')
  if msg then
    return {
      {
        lnum = 0,
        col = 0,
        message = msg,
        severity = vim.diagnostic.severity.ERROR,
      },
    }
  end
  return {}
end

---@type preview.ProviderConfig
M.typst = {
  ft = 'typst',
  cmd = { 'typst', 'compile' },
  args = function(ctx)
    return { '--diagnostic-format', 'short', ctx.file }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.typ$', '.pdf'))
  end,
  error_parser = function(output)
    return parse_typst(output)
  end,
  failure_summary = function(result)
    return summarize_typst(result.output or '')
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.typ$', '.pdf')) }
  end,
  open = true,
  reload = function(ctx)
    return { 'typst', 'watch', '--diagnostic-format', 'short', ctx.file }
  end,
}

---@type preview.ProviderConfig
M.latex = {
  ft = 'tex',
  cmd = { 'latexmk' },
  args = function(ctx)
    return {
      '-pdf',
      '-interaction=nonstopmode',
      '-synctex=1',
      '-pdflatex=pdflatex -file-line-error -interaction=nonstopmode %O %S',
      ctx.file,
    }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.tex$', '.pdf'))
  end,
  error_parser = function(output)
    return parse_latexmk(output)
  end,
  failure_summary = function(result)
    return summarize_latexmk(result.output or '')
  end,
  clean = function(ctx)
    return { 'latexmk', '-c', ctx.file }
  end,
  open = true,
}

---@type preview.ProviderConfig
M.pdflatex = {
  ft = 'tex',
  cmd = { 'pdflatex' },
  args = function(ctx)
    return { '-interaction=nonstopmode', '-file-line-error', '-synctex=1', ctx.file }
  end,
  env = {
    max_print_line = '10000',
  },
  output = function(ctx)
    return (ctx.file:gsub('%.tex$', '.pdf'))
  end,
  error_parser = function(output)
    return parse_latexmk(output)
  end,
  failure_summary = function(result)
    return summarize_pdflatex(result.output or '')
  end,
  clean = function(ctx)
    local base = ctx.file:gsub('%.tex$', '')
    return { 'rm', '-f', base .. '.pdf', base .. '.aux', base .. '.log', base .. '.synctex.gz' }
  end,
  open = true,
}

---@type preview.ProviderConfig
M.tectonic = {
  ft = 'tex',
  cmd = { 'tectonic' },
  args = function(ctx)
    return { ctx.file }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.tex$', '.pdf'))
  end,
  error_parser = function(output)
    return parse_latexmk(output)
  end,
  failure_summary = summarize_tectonic,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.tex$', '.pdf')) }
  end,
  open = true,
}

---@type preview.ProviderConfig
M.markdown = {
  ft = 'markdown',
  cmd = { 'pandoc' },
  args = function(ctx)
    return { ctx.file, '-s', '--katex', '-o', ctx.output }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.md$', '.html'))
  end,
  error_parser = function(output)
    return parse_pandoc(output)
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.md$', '.html')) }
  end,
  open = true,
  reload = true,
}

---@type preview.ProviderConfig
M.github = {
  ft = 'markdown',
  cmd = { 'pandoc' },
  args = function(ctx)
    local template = vim.api.nvim_get_runtime_file('lua/preview/templates/gfm.html', false)[1]
    local args = {
      '-f',
      'gfm',
      ctx.file,
      '-s',
      '--katex',
      '--no-highlight',
      '-o',
      ctx.output,
    }
    if template then
      vim.list_extend(args, { '--template', template })
    end
    return args
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.md$', '.html'))
  end,
  error_parser = function(output)
    return parse_pandoc(output)
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.md$', '.html')) }
  end,
  open = true,
  reload = true,
}

---@type preview.ProviderConfig
M.asciidoctor = {
  ft = 'asciidoc',
  cmd = { 'asciidoctor' },
  args = function(ctx)
    return { '--failure-level', 'ERROR', ctx.file, '-o', ctx.output }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.adoc$', '.html'))
  end,
  error_parser = function(output)
    return parse_asciidoctor(output)
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.adoc$', '.html')) }
  end,
  open = true,
  reload = true,
}

---@type preview.ProviderConfig
M.plantuml = {
  ft = 'plantuml',
  cmd = { 'plantuml' },
  args = function(ctx)
    return { '-tsvg', ctx.file }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.puml$', '.svg'))
  end,
  error_parser = function(output)
    local diagnostics = {}
    for line in output:gmatch('[^\r\n]+') do
      local lnum = line:match('^Error line (%d+) in file:')
      if lnum then
        table.insert(diagnostics, {
          lnum = tonumber(lnum) - 1,
          col = 0,
          message = line,
          severity = vim.diagnostic.severity.ERROR,
        })
      end
    end
    return diagnostics
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.puml$', '.svg')) }
  end,
  open = true,
}

---@type preview.ProviderConfig
M.mermaid = {
  ft = 'mermaid',
  cmd = { 'mmdc' },
  args = function(ctx)
    return { '-i', ctx.file, '-o', ctx.output }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.mmd$', '.svg'))
  end,
  error_parser = function(output)
    return parse_mermaid(output)
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.mmd$', '.svg')) }
  end,
  open = true,
}

---@type preview.ProviderConfig
M.quarto = {
  ft = 'quarto',
  cmd = { 'quarto' },
  args = function(ctx)
    return { 'render', ctx.file, '--to', 'html', '--embed-resources' }
  end,
  output = function(ctx)
    return (ctx.file:gsub('%.qmd$', '.html'))
  end,
  error_parser = function(output)
    return parse_quarto(output)
  end,
  clean = function(ctx)
    local base = ctx.file:gsub('%.qmd$', '')
    return { 'rm', '-rf', base .. '.html', base .. '_files' }
  end,
  open = true,
  reload = true,
}

return M
