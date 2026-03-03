local M = {}

---@type preview.ProviderConfig
M.typst = {
  ft = 'typst',
  cmd = { 'typst', 'compile' },
  args = function(ctx)
    return { ctx.file }
  end,
  output = function(ctx)
    return ctx.file:gsub('%.typ$', '.pdf')
  end,
  open = { 'xdg-open' },
}

---@type preview.ProviderConfig
M.latex = {
  ft = 'tex',
  cmd = { 'latexmk' },
  args = function(ctx)
    return { '-pdf', '-interaction=nonstopmode', ctx.file }
  end,
  output = function(ctx)
    return ctx.file:gsub('%.tex$', '.pdf')
  end,
  clean = function(ctx)
    return { 'latexmk', '-c', ctx.file }
  end,
  open = { 'xdg-open' },
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
    return ctx.file:gsub('%.md$', '.html')
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.md$', '.html')) }
  end,
  open = { 'xdg-open' },
}

---@type preview.ProviderConfig
M.github = {
  ft = 'markdown',
  cmd = { 'pandoc' },
  args = function(ctx)
    local output = ctx.file:gsub('%.md$', '.html')
    return {
      ctx.file,
      '-s',
      '--embed-resources',
      '--css',
      'https://cdn.jsdelivr.net/gh/pixelbrackets/gfm-stylesheet@master/github.css',
      '-o',
      output,
    }
  end,
  output = function(ctx)
    return ctx.file:gsub('%.md$', '.html')
  end,
  clean = function(ctx)
    return { 'rm', '-f', (ctx.file:gsub('%.md$', '.html')) }
  end,
  open = { 'xdg-open' },
}

return M
