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

    it('returns args with diagnostic format and file path', function()
      local args = presets.typst.args(ctx)
      assert.is_table(args)
      assert.are.same({ '--diagnostic-format', 'short', '/tmp/document.typ' }, args)
    end)

    it('returns pdf output path', function()
      local output = presets.typst.output(ctx)
      assert.is_string(output)
      assert.are.equal('/tmp/document.pdf', output)
    end)

    it('has open enabled', function()
      assert.is_true(presets.typst.open)
    end)

    it('has reload as a function', function()
      assert.is_function(presets.typst.reload)
    end)

    it('reload returns typst watch command', function()
      local result = presets.typst.reload(ctx)
      assert.is_table(result)
      assert.are.equal('typst', result[1])
      assert.are.equal('watch', result[2])
      assert.are.equal(ctx.file, result[3])
    end)

    it('parses errors from stderr', function()
      local stderr = table.concat({
        'main.typ:5:23: error: unexpected token',
        'main.typ:12:1: warning: unused variable',
      }, '\n')
      local diagnostics = presets.typst.error_parser(stderr, ctx)
      assert.is_table(diagnostics)
      assert.are.equal(2, #diagnostics)
      assert.are.equal(4, diagnostics[1].lnum)
      assert.are.equal(22, diagnostics[1].col)
      assert.are.equal('unexpected token', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
      assert.is_nil(diagnostics[1].source)
      assert.are.equal(11, diagnostics[2].lnum)
      assert.are.equal(0, diagnostics[2].col)
      assert.are.equal('unused variable', diagnostics[2].message)
      assert.are.equal(vim.diagnostic.severity.WARN, diagnostics[2].severity)
    end)

    it('returns empty table for clean stderr', function()
      local diagnostics = presets.typst.error_parser('', ctx)
      assert.are.same({}, diagnostics)
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
      assert.are.same({
        '-pdf',
        '-interaction=nonstopmode',
        '-synctex=1',
        '-pdflatex=pdflatex -file-line-error -interaction=nonstopmode %O %S',
        '/tmp/document.tex',
      }, args)
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
      assert.is_true(presets.latex.open)
    end)

    it('parses file-line-error format from output', function()
      local output = table.concat({
        './document.tex:10: Undefined control sequence.',
        'l.10 \\badcommand',
        'Collected error summary (may duplicate other messages):',
        "  pdflatex: Command for 'pdflatex' gave return code 256",
      }, '\n')
      local diagnostics = presets.latex.error_parser(output, tex_ctx)
      assert.is_table(diagnostics)
      assert.is_true(#diagnostics > 0)
      assert.are.equal(9, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('Undefined control sequence.', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    end)

    it('parses collected error summary', function()
      local output = table.concat({
        'Latexmk: Errors, so I did not complete making targets',
        'Collected error summary (may duplicate other messages):',
        "  pdflatex: Command for 'pdflatex' gave return code 256",
      }, '\n')
      local diagnostics = presets.latex.error_parser(output, tex_ctx)
      assert.is_table(diagnostics)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(0, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal(
        "pdflatex: Command for 'pdflatex' gave return code 256",
        diagnostics[1].message
      )
    end)

    it('returns empty table for clean stderr', function()
      local diagnostics = presets.latex.error_parser('', tex_ctx)
      assert.are.same({}, diagnostics)
    end)
  end)

  describe('markdown', function()
    local md_ctx = {
      bufnr = 1,
      file = '/tmp/document.md',
      root = '/tmp',
      ft = 'markdown',
      output = '/tmp/document.html',
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
      assert.is_true(presets.markdown.open)
    end)

    it('has reload enabled for SSE', function()
      assert.is_true(presets.markdown.reload)
    end)

    it('parses YAML metadata errors with multiline message', function()
      local output = table.concat({
        'Error parsing YAML metadata at "/tmp/test.md" (line 1, column 1):',
        'YAML parse exception at line 1, column 9:',
        'mapping values are not allowed in this context',
      }, '\n')
      local diagnostics = presets.markdown.error_parser(output, md_ctx)
      assert.is_table(diagnostics)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(0, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('mapping values are not allowed in this context', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    end)

    it('parses Error at format', function()
      local output = 'Error at "source" (line 75, column 1): unexpected end of input'
      local diagnostics = presets.markdown.error_parser(output, md_ctx)
      assert.is_table(diagnostics)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(74, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('unexpected end of input', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    end)

    it('parses generic pandoc errors', function()
      local output = 'pandoc: Could not find data file templates/default.html5'
      local diagnostics = presets.markdown.error_parser(output, md_ctx)
      assert.is_table(diagnostics)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(0, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('Could not find data file templates/default.html5', diagnostics[1].message)
    end)

    it('returns empty table for clean output', function()
      local diagnostics = presets.markdown.error_parser('', md_ctx)
      assert.are.same({}, diagnostics)
    end)
  end)

  describe('github', function()
    local md_ctx = {
      bufnr = 1,
      file = '/tmp/document.md',
      root = '/tmp',
      ft = 'markdown',
      output = '/tmp/document.html',
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
        '-f',
        'gfm',
        '/tmp/document.md',
        '-s',
        '--embed-resources',
        '--css',
        'https://cdn.jsdelivr.net/gh/pixelbrackets/gfm-stylesheet@master/dist/gfm.css',
        '-o',
        '/tmp/document.html',
      }, args)
    end)

    it('args include -f and gfm flags', function()
      local args = presets.github.args(md_ctx)
      local idx = nil
      for i, v in ipairs(args) do
        if v == '-f' then
          idx = i
          break
        end
      end
      assert.is_not_nil(idx)
      assert.are.equal('gfm', args[idx + 1])
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
      assert.is_true(presets.github.open)
    end)

    it('has reload enabled for SSE', function()
      assert.is_true(presets.github.reload)
    end)

    it('parses YAML metadata errors with multiline message', function()
      local output = table.concat({
        'Error parsing YAML metadata at "/tmp/test.md" (line 1, column 1):',
        'YAML parse exception at line 1, column 9:',
        'mapping values are not allowed in this context',
      }, '\n')
      local diagnostics = presets.github.error_parser(output, md_ctx)
      assert.is_table(diagnostics)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(0, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('mapping values are not allowed in this context', diagnostics[1].message)
    end)

    it('parses Error at format', function()
      local output = 'Error at "document.md" (line 12, column 5): unexpected "}" expecting letter'
      local diagnostics = presets.github.error_parser(output, md_ctx)
      assert.is_table(diagnostics)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(11, diagnostics[1].lnum)
      assert.are.equal(4, diagnostics[1].col)
      assert.are.equal('unexpected "}" expecting letter', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    end)

    it('returns empty table for clean output', function()
      local diagnostics = presets.github.error_parser('', md_ctx)
      assert.are.same({}, diagnostics)
    end)
  end)
end)
