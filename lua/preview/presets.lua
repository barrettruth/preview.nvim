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
  open = true,
}

---@type preview.ProviderConfig
M.latex = {
  ft = 'tex',
  cmd = { 'latexmk' },
  args = function(ctx)
    return {
      '-pdf',
      '-interaction=nonstopmode',
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
  clean = function(ctx)
    return { 'latexmk', '-c', ctx.file }
  end,
  open = true,
}

---@type preview.ProviderConfig
M.markdown = {
  ft = 'markdown',
  cmd = { 'pandoc' },
  args = function(ctx)
    local output = ctx.file:gsub('%.md$', '.html')
    return { ctx.file, '-s', '--embed-resources', '-o', output }
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
}

---@type preview.ProviderConfig
M.github = {
  ft = 'markdown',
  cmd = { 'pandoc' },
  args = function(ctx)
    local output = ctx.file:gsub('%.md$', '.html')
    return {
      '-f',
      'gfm',
      ctx.file,
      '-s',
      '--embed-resources',
      '--css',
      'https://cdn.jsdelivr.net/gh/pixelbrackets/gfm-stylesheet@master/dist/gfm.css',
      '-o',
      output,
    }
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
}

return M
