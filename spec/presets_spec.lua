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
  end)

  describe('latex', function()
    local tex_ctx = {
      bufnr = 1,
      file = '/tmp/document.tex',
      root = '/tmp',
      ft = 'tex',
    }

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
  end)

  describe('markdown', function()
    local md_ctx = {
      bufnr = 1,
      file = '/tmp/document.md',
      root = '/tmp',
      ft = 'markdown',
    }

    it('has cmd', function()
      assert.are.same({ 'pandoc' }, presets.markdown.cmd)
    end)

    it('returns args with file and output flag', function()
      local args = presets.markdown.args(md_ctx)
      assert.is_table(args)
      assert.are.same({ '/tmp/document.md', '-o', '/tmp/document.pdf' }, args)
    end)

    it('returns pdf output path', function()
      local output = presets.markdown.output(md_ctx)
      assert.is_string(output)
      assert.are.equal('/tmp/document.pdf', output)
    end)
  end)
end)
