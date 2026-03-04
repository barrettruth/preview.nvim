# preview.nvim

**Async document compilation for Neovim**

An extensible framework for compiling documents (LaTeX, Typst, Markdown, etc.)
asynchronously with error diagnostics.

## Features

- Async compilation via `vim.system()`
- Built-in presets for Typst, LaTeX (latexmk, pdflatex, tectonic), Markdown, GitHub-flavored Markdown, AsciiDoc, and Quarto
- Compiler errors as native `vim.diagnostic`
- User events for extensibility (`PreviewCompileStarted`,
  `PreviewCompileSuccess`, `PreviewCompileFailed`)

## Requirements

- Neovim 0.11+

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
  rst = {
    cmd = { 'rst2html' },
    args = function(ctx)
      return { ctx.file, ctx.output }
    end,
    output = function(ctx)
      return ctx.file:gsub('%.rst$', '.html')
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
open the output with `vim.ui.open()` after the first successful compilation in
toggle/watch mode. For a specific application, pass a command table:

```lua
require('preview').setup({
  typst = { open = { 'sioyek', '--new-instance' } },
})
```
