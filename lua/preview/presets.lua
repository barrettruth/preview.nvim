local M = {}

---@type preview.ProviderConfig
M.typst = {
  cmd = { 'typst', 'compile' },
  args = function(ctx)
    return { ctx.file }
  end,
  output = function(ctx)
    return ctx.file:gsub('%.typ$', '.pdf')
  end,
}

---@type preview.ProviderConfig
M.latex = {
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
}

---@type preview.ProviderConfig
M.markdown = {
  cmd = { 'pandoc' },
  args = function(ctx)
    local output = ctx.file:gsub('%.md$', '.pdf')
    return { ctx.file, '-o', output }
  end,
  output = function(ctx)
    return ctx.file:gsub('%.md$', '.pdf')
  end,
}

return M
