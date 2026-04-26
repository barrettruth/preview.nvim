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

local function is_pandoc_yaml_header(line)
  return type(line) == 'string'
    and line:match('^Error parsing YAML metadata at ".+" %(line %d+, column %d+%):$') ~= nil
end

local function pandoc_yaml_detail(lines, start)
  for j = start, #lines do
    local next_line = lines[j]
    if next_line then
      next_line = next_line:match('^%s*(.-)%s*$')
    end
    if next_line == '' then
      break
    end
    if
      next_line
      and not next_line:match('^YAML parse exception')
      and not next_line:match('^while ')
      and not next_line:match('^Consider ')
    then
      return next_line
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
        if is_pandoc_yaml_header(line) then
          msg = pandoc_yaml_detail(lines, i + 1) or ''
        else
          for j = i + 1, #lines do
            local next_line = lines[j] and lines[j]:match('^%s*(.-)%s*$')
            if next_line == '' then
              break
            end
            if next_line and next_line ~= '' then
              msg = next_line
              break
            end
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

---@param path string
---@return string
local function basename(path)
  return path:match('([^/\\]+)$') or path
end

---@param line string?
---@return string?
local function trim_line(line)
  if type(line) ~= 'string' then
    return nil
  end
  line = line:match('^%s*(.-)%s*$')
  if line == '' then
    return nil
  end
  return line
end

local function pandoc_next_detail(lines, start, stop_on_blank)
  for j = start, #lines do
    local next_raw = lines[j]
    local next_line = trim_line(next_raw)
    if next_line then
      return next_line
    end
    if stop_on_blank and type(next_raw) == 'string' and next_raw:match('^%s*$') then
      break
    end
  end
end

local function pandoc_error_at_detail(line, lines, start, stop_on_blank)
  local src, msg = line:match('^Error at "(.-)" %(line %d+, column %d+%):%s*(.*)$')
  if not src then
    return nil
  end
  msg = trim_line(msg) or pandoc_next_detail(lines, start, stop_on_blank)
  if msg then
    return src, msg
  end
end

local function pandoc_filter_detail(line, lines, start)
  local filter = line:match('^Error running filter (.+):$')
  if not filter then
    return nil
  end
  local next_line = pandoc_next_detail(lines, start, false)
  if next_line then
    local detail = next_line:match('^.+:(%d+:%s*.+)$') or next_line
    return filter, detail
  end
end

local function pandoc_bibliography_detail(line, lines, start)
  local bibliography = line:match('^Error reading bibliography file (.+):$')
  if not bibliography then
    return nil
  end
  for j = start, #lines do
    local next_line = trim_line(lines[j])
    if next_line and not next_line:match('^%(') then
      return bibliography, next_line
    end
  end
end

local function summarize_pandoc_common(output, opts)
  local lines = vim.split(output, '\n', { plain = true, trimempty = false })
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if is_pandoc_yaml_header(line) then
      local summary = pandoc_yaml_detail(lines, i + 1)
      if summary then
        return opts.yaml_prefix .. summary
      end
    end

    local src, msg = pandoc_error_at_detail(line, lines, i + 1, opts.error_at_stop_on_blank)
    if src and msg then
      return opts.error_at_summary(src, msg)
    end

    if opts.include_filter then
      local filter, detail = pandoc_filter_detail(line, lines, i + 1)
      if filter and detail then
        return 'pandoc filter ' .. basename(filter) .. ': ' .. detail
      end
    end

    if opts.include_bibliography then
      local bibliography, detail = pandoc_bibliography_detail(line, lines, i + 1)
      if bibliography and detail then
        return 'pandoc: bibliography ' .. basename(bibliography) .. ': ' .. detail
      end
    end

    local pandoc_msg = line:match('^pandoc: (.+)$')
    if pandoc_msg then
      return opts.pandoc_message(pandoc_msg)
    end

    local data_file = line:match('^Could not find data file (.+)$')
    if data_file and opts.data_file_summary then
      return opts.data_file_summary(data_file, line)
    end

    for _, pattern in ipairs(opts.passthrough_patterns or {}) do
      if line:match(pattern) then
        return opts.line_summary(line)
      end
    end

    i = i + 1
  end
end

---@param output string
---@return string?
local function summarize_pandoc(output)
  return summarize_pandoc_common(output, {
    yaml_prefix = 'pandoc: YAML metadata: ',
    error_at_stop_on_blank = false,
    error_at_summary = function(src, msg)
      return 'pandoc: ' .. basename(src) .. ': ' .. msg
    end,
    include_filter = true,
    include_bibliography = true,
    pandoc_message = function(msg)
      return 'pandoc: ' .. msg
    end,
    data_file_summary = function(data_file)
      return 'pandoc: could not find data file ' .. basename(data_file)
    end,
    passthrough_patterns = {
      '^Unknown output format',
      '^Unknown option',
      '^Argument of ',
    },
    line_summary = function(line)
      return 'pandoc: ' .. line
    end,
  })
end

---@param output string
---@return string?
local function summarize_github_pandoc(output)
  return summarize_pandoc_common(output, {
    yaml_prefix = 'YAML metadata: ',
    error_at_stop_on_blank = true,
    error_at_summary = function(src, msg)
      return basename(src) .. ': ' .. msg
    end,
    include_filter = false,
    include_bibliography = false,
    pandoc_message = function(msg)
      return msg
    end,
    data_file_summary = function(_, line)
      return line
    end,
    passthrough_patterns = {
      '^Unknown option',
      '^The extension ',
    },
    line_summary = function(line)
      return line
    end,
  })
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

---@param output string?
---@return string?
local function summarize_asciidoctor(output)
  if type(output) ~= 'string' or output == '' then
    return nil
  end
  local first_warning
  for line in output:gmatch('[^\r\n]+') do
    local severity, body = line:match('^asciidoctor: (%u+): (.+)$')
    if severity == 'ERROR' or severity == 'FATAL' then
      return body
    end
    if severity == 'WARNING' and not first_warning then
      first_warning = body
    end
    local failed = line:match('^asciidoctor: FAILED: (.+)$')
    if failed then
      return failed
    end
    local invalid = line:match('^asciidoctor: invalid (.+)$')
    if invalid then
      return 'invalid ' .. invalid
    end
  end
  return first_warning
end

---@param line string?
---@return integer?
local function plantuml_error_line(line)
  local lnum = type(line) == 'string' and line:match('^Error line (%d+) in file:')
  return lnum and tonumber(lnum) or nil
end

---@param output string?
---@return string?
local function summarize_plantuml(output)
  if type(output) ~= 'string' or output == '' then
    return nil
  end
  for line in output:gmatch('[^\r\n]+') do
    local lnum = plantuml_error_line(line)
    if lnum then
      return string.format('plantuml: error on line %d (see :Preview output)', lnum)
    end
    if line == 'No diagram found' then
      return 'plantuml: no diagram found (see :Preview output)'
    end
  end
end

---@param line string?
---@return integer?
local function mermaid_parse_error_line(line)
  if type(line) ~= 'string' then
    return nil
  end
  local lnum = line:match('^Error: Parse error on line (%d+):$')
    or line:match('^Parse error on line (%d+):$')
  return lnum and tonumber(lnum) or nil
end

---@param line string?
---@return string?
local function mermaid_expectation(line)
  if type(line) ~= 'string' then
    return nil
  end
  return line:match("^%s*(Expecting '.-got '.+')%s*$")
end

---@param output string?
---@return string?
local function summarize_mermaid(output)
  if type(output) ~= 'string' or output == '' then
    return nil
  end
  local lnum
  local msg
  for line in output:gmatch('[^\r\n]+') do
    lnum = lnum or mermaid_parse_error_line(line)
    msg = msg or mermaid_expectation(line)
  end
  if lnum and msg then
    return string.format('Parse error on line %d: %s', lnum, msg)
  end
end

---@param output string
---@return preview.Diagnostic[]
local function parse_mermaid(output)
  local lnum
  local msg
  for line in output:gmatch('[^\r\n]+') do
    lnum = lnum or mermaid_parse_error_line(line)
    msg = msg or mermaid_expectation(line)
  end
  if not lnum then
    return {}
  end
  return {
    {
      lnum = lnum - 1,
      col = 0,
      message = msg or 'parse error',
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

local QUARTO_NOISE = {
  ['Validation of YAML front matter failed.'] = true,
  ['Render failed due to invalid YAML.'] = true,
  ['Error encountered when rendering files'] = true,
}

---@param result preview.Result
---@return string?
local function summarize_quarto(result)
  local output = result.output or ''
  if output == '' then
    return nil
  end
  output = output:gsub('\27%[[0-9;]*m', '')
  for line in output:gmatch('[^\r\n]+') do
    local msg = line:match('^ERROR:%s*(.+)$')
    if msg then
      msg = msg:gsub('^%s*(.-)%s*$', '%1')
      if not QUARTO_NOISE[msg] and not msg:match('^In file ') then
        return msg
      end
    end
  end
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
  failure_summary = function(result)
    return summarize_pandoc(result.output or '')
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
  failure_summary = function(result)
    return summarize_github_pandoc(result.output or '')
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
  failure_summary = function(result)
    return summarize_asciidoctor(result.output)
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
      local lnum = plantuml_error_line(line)
      if lnum then
        table.insert(diagnostics, {
          lnum = lnum - 1,
          col = 0,
          message = line,
          severity = vim.diagnostic.severity.ERROR,
        })
      end
    end
    return diagnostics
  end,
  failure_summary = function(result)
    return summarize_plantuml(result.output)
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
  failure_summary = function(result)
    return summarize_mermaid(result.output)
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
  failure_summary = function(result)
    return summarize_quarto(result)
  end,
  clean = function(ctx)
    local base = ctx.file:gsub('%.qmd$', '')
    return { 'rm', '-rf', base .. '.html', base .. '_files' }
  end,
  open = true,
  reload = true,
}

return M
