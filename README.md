# render.nvim

Async document compilation for Neovim.

A framework for compiling documents (LaTeX, Typst, Markdown, etc.)
asynchronously with error diagnostics. Ships with zero defaults — you
configure your own providers.

## Features

- Async compilation via `vim.system()`
- Compiler errors as native `vim.diagnostic`
- User events for extensibility (`RenderCompileStarted`,
  `RenderCompileSuccess`, `RenderCompileFailed`)
- `:checkhealth` integration
- Zero dependencies beyond Neovim 0.10.0+

## Requirements

- Neovim >= 0.10.0
- A compiler binary for each provider you configure

## Installation

```lua
-- lazy.nvim
{ 'barrettruth/render.nvim' }
```

```vim
" luarocks
:Rocks install render.nvim
```

## Configuration

```lua
vim.g.render = {
  providers = {
    typst = {
      cmd = { 'typst', 'compile' },
      args = function(ctx)
        return { ctx.file }
      end,
      output = function(ctx)
        return ctx.file:gsub('%.typ$', '.pdf')
      end,
    },
    latexmk = {
      cmd = { 'latexmk' },
      args = { '-pdf', '-interaction=nonstopmode' },
      clean = { 'latexmk', '-c' },
    },
  },
  providers_by_ft = {
    typst = 'typst',
    tex = 'latexmk',
  },
}
```

## Documentation

See `:help render.nvim` for full documentation.
