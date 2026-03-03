# preview.nvim

Async document compilation for Neovim.

A framework for compiling documents (LaTeX, Typst, Markdown, etc.)
asynchronously with error diagnostics. Ships with zero defaults — you configure
your own providers.

## Features

- Async compilation via `vim.system()`
- Compiler errors as native `vim.diagnostic`
- User events for extensibility (`PreviewCompileStarted`,
  `PreviewCompileSuccess`, `PreviewCompileFailed`)
- `:checkhealth` integration
- Zero dependencies beyond Neovim 0.11.0+

## Requirements

- Neovim >= 0.11.0
- A compiler binary for each provider you configure

## Installation

```lua
-- lazy.nvim
{ 'barrettruth/preview.nvim' }
```

```vim
" luarocks
:Rocks install preview.nvim
```

## Configuration

Use built-in presets for common tools:

```lua
local presets = require('preview.presets')
vim.g.preview = {
  providers = {
    typst = presets.typst,
    tex = presets.latex,
    markdown = presets.markdown,
  },
}
```

Or define providers manually:

```lua
vim.g.preview = {
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
  },
}
```

## Documentation

See `:help preview.nvim` for full documentation.
