describe('presets', function()
  local presets

  before_each(function()
    presets = require('preview.presets')
  end)

  local ctx = {
    bufnr = 1,
    file = '/tmp/document.typ',
    root = '/tmp',
    ft = 'typst',
  }

  describe('typst', function()
    it('has ft', function()
      assert.are.equal('typst', presets.typst.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'typst', 'compile' }, presets.typst.cmd)
    end)

    it('returns args with file path', function()
      local args = presets.typst.args(ctx)
      assert.is_table(args)
      assert.are.same({ '/tmp/document.typ' }, args)
    end)

    it('returns pdf output path', function()
      local output = presets.typst.output(ctx)
      assert.is_string(output)
      assert.are.equal('/tmp/document.pdf', output)
    end)

    it('has open enabled', function()
      assert.are.same({ 'xdg-open' }, presets.typst.open)
    end)
  end)

  describe('latex', function()
    local tex_ctx = {
      bufnr = 1,
      file = '/tmp/document.tex',
      root = '/tmp',
      ft = 'tex',
    }

    it('has ft', function()
      assert.are.equal('tex', presets.latex.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'latexmk' }, presets.latex.cmd)
    end)

    it('returns args with pdf flag and file path', function()
      local args = presets.latex.args(tex_ctx)
      assert.is_table(args)
      assert.are.same({ '-pdf', '-interaction=nonstopmode', '/tmp/document.tex' }, args)
    end)

    it('returns pdf output path', function()
      local output = presets.latex.output(tex_ctx)
      assert.is_string(output)
      assert.are.equal('/tmp/document.pdf', output)
    end)

    it('returns clean command', function()
      local clean = presets.latex.clean(tex_ctx)
      assert.is_table(clean)
      assert.are.same({ 'latexmk', '-c', '/tmp/document.tex' }, clean)
    end)

    it('has open enabled', function()
      assert.are.same({ 'xdg-open' }, presets.latex.open)
    end)
  end)

  describe('markdown', function()
    local md_ctx = {
      bufnr = 1,
      file = '/tmp/document.md',
      root = '/tmp',
      ft = 'markdown',
    }

    it('has ft', function()
      assert.are.equal('markdown', presets.markdown.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'pandoc' }, presets.markdown.cmd)
    end)

    it('returns args with standalone and embed-resources flags', function()
      local args = presets.markdown.args(md_ctx)
      assert.is_table(args)
      assert.are.same(
        { '/tmp/document.md', '-s', '--embed-resources', '-o', '/tmp/document.html' },
        args
      )
    end)

    it('returns html output path', function()
      local output = presets.markdown.output(md_ctx)
      assert.is_string(output)
      assert.are.equal('/tmp/document.html', output)
    end)

    it('returns clean command', function()
      local clean = presets.markdown.clean(md_ctx)
      assert.is_table(clean)
      assert.are.same({ 'rm', '-f', '/tmp/document.html' }, clean)
    end)

    it('has open enabled', function()
      assert.are.same({ 'xdg-open' }, presets.markdown.open)
    end)
  end)

  describe('github', function()
    local md_ctx = {
      bufnr = 1,
      file = '/tmp/document.md',
      root = '/tmp',
      ft = 'markdown',
    }

    it('has ft', function()
      assert.are.equal('markdown', presets.github.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'pandoc' }, presets.github.cmd)
    end)

    it('returns args with standalone, embed-resources, and css flags', function()
      local args = presets.github.args(md_ctx)
      assert.is_table(args)
      assert.are.same({
        '/tmp/document.md',
        '-s',
        '--embed-resources',
        '--css',
        'https://cdn.jsdelivr.net/gh/pixelbrackets/gfm-stylesheet@master/github.css',
        '-o',
        '/tmp/document.html',
      }, args)
    end)

    it('returns html output path', function()
      local output = presets.github.output(md_ctx)
      assert.is_string(output)
      assert.are.equal('/tmp/document.html', output)
    end)

    it('returns clean command', function()
      local clean = presets.github.clean(md_ctx)
      assert.is_table(clean)
      assert.are.same({ 'rm', '-f', '/tmp/document.html' }, clean)
    end)

    it('has open enabled', function()
      assert.are.same({ 'xdg-open' }, presets.github.open)
    end)
  end)
end)
