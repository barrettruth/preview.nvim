# preview.nvim

**Universal document previewer for Neovim**

An extensible framework for compiling and previewing _any_ documents (LaTeX,
Typst, Markdown, etc.)&mdash;diagnostics included.

<video src="https://github.com/user-attachments/assets/3b4fbc31-c1c4-4429-a9dc-a68d6185ab2e" width="100%" controls></video>

## Features

- Async compilation via `vim.system()`
- Built-in presets for Typst, LaTeX (latexmk, pdflatex, tectonic), Markdown,
  GitHub-flavored Markdown, AsciiDoc, and Quarto
- Compiler errors via `vim.diagnostic` or quickfix
- Previewer auto-close on buffer deletion

## Requirements

- Neovim 0.11+

## Installation

With lazy.nvim:

```lua
{
  'barrettruth/preview.nvim',
  init = function()
    vim.g.preview = { typst = true, latex = true }
  end,
}
```

Or via [luarocks](https://luarocks.org/modules/barrettruth/preview.nvim):

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
vim.g.preview = {
  rst = {
    cmd = { 'rst2html' },
    args = function(ctx)
      return { ctx.file, ctx.output }
    end,
    output = function(ctx)
      return ctx.file:gsub('%.rst$', '.html')
    end,
  },
}
```

**Q: How do I override a preset?**

```lua
vim.g.preview = {
  typst = { env = { TYPST_FONT_PATHS = '/usr/share/fonts' } },
}
```

**Q: How do I automatically open the output file?**

Set `open = true` on your provider (all built-in presets have this enabled) to
open the output with `vim.ui.open()` after the first successful compilation in
toggle/watch mode. For a specific application, pass a command table:

```lua
vim.g.preview = {
  typst = { open = { 'sioyek', '--new-instance' } },
}
```
