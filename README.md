# preview.nvim

**Async document compilation for Neovim**

An extensible framework for compiling documents (LaTeX, Typst, Markdown, etc.)
asynchronously with error diagnostics.

## Features

- Async compilation via `vim.system()`
- Compiler errors as native `vim.diagnostic`
- User events for extensibility (`PreviewCompileStarted`,
  `PreviewCompileSuccess`, `PreviewCompileFailed`)
- Built-in presets for Typst, LaTeX, Markdown, and GitHub-flavored Markdown
- `:checkhealth` integration
- Zero dependencies beyond Neovim 0.11.0+

## Requirements

- Neovim 0.11.0+

## Installation

Install with your package manager of choice or via
[luarocks](https://luarocks.org/modules/barrettruth/preview.nvim):

```
luarocks install preview.nvim
```

## Documentation

```vim
:help preview.nvim
```

## FAQ

**Q: How do I define a custom provider?**

```lua
require('preview').setup({
  typst = {
    cmd = { 'typst', 'compile' },
    args = function(ctx)
      return { ctx.file }
    end,
    output = function(ctx)
      return ctx.file:gsub('%.typ$', '.pdf')
    end,
  },
})
```

**Q: How do I override a preset?**

```lua
require('preview').setup({
  typst = { env = { TYPST_FONT_PATHS = '/usr/share/fonts' } },
})
```

**Q: How do I automatically open the output file?**

Set `open = true` on your provider (all built-in presets have this enabled) to
open the output with `vim.ui.open()` after the first successful compilation. For
a specific application, pass a command table:

```lua
require('preview').setup({
  typst = { open = { 'sioyek', '--new-instance' } },
})
```
