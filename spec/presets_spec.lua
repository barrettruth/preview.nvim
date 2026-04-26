local helpers = require('spec.helpers')

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

  local function pandoc_result(path, code)
    local output = helpers.read_fixture(path)
    return { code = code or 1, stdout = '', stderr = output, output = output }
  end

  local function define_pandoc_failure_summary_tests(get_provider, md_ctx)
    describe('failure_summary', function()
      it('produces YAML failure summary', function()
        assert.are.equal(
          'pandoc: YAML metadata: mapping values are not allowed in this context',
          get_provider().failure_summary(pandoc_result('pandoc_yaml_simple.txt'), md_ctx)
        )
      end)

      it('walks "while parsing" YAML blocks to the deepest cause', function()
        assert.are.equal(
          "pandoc: YAML metadata: did not find expected ',' or ']'",
          get_provider().failure_summary(pandoc_result('pandoc_yaml_flow.txt'), md_ctx)
        )
      end)

      it('drops HasCallStack noise from pandoc IO failures', function()
        local summary = get_provider().failure_summary(pandoc_result('pandoc_io_error.txt'), md_ctx)
        assert.are.equal(
          'pandoc: /nonexistent/file.md: withBinaryFile: does not exist (No such file or directory)',
          summary
        )
        assert.is_nil(summary:find('HasCallStack', 1, true))
        assert.is_nil(summary:find('Exception.hs', 1, true))
      end)

      it('strips the nix-store path from missing template errors', function()
        assert.are.equal(
          'pandoc: could not find data file nonexistent_template.html5',
          get_provider().failure_summary(pandoc_result('pandoc_missing_data.txt'), md_ctx)
        )
      end)

      it('handles bibliography errors with filename context', function()
        assert.are.equal(
          "pandoc: bibliography 08_bib.bib: unexpected 'a'",
          get_provider().failure_summary(pandoc_result('pandoc_bibliography.txt'), md_ctx)
        )
      end)

      it('handles reader error-at failures with filename context', function()
        assert.are.equal(
          "pandoc: 08_bib.bib: unexpected 'a'",
          get_provider().failure_summary(pandoc_result('pandoc_error_at.txt'), md_ctx)
        )
      end)

      it('handles lua filter errors without stack traceback noise', function()
        local summary = get_provider().failure_summary(pandoc_result('pandoc_filter.txt'), md_ctx)
        assert.are.equal('pandoc filter 19_filter.lua: 2: boom from filter', summary)
        assert.is_nil(summary:find('stack traceback', 1, true))
      end)

      it('handles unknown output formats', function()
        assert.are.equal(
          'pandoc: Unknown output format bogus_format',
          get_provider().failure_summary(pandoc_result('pandoc_unknown_output.txt'), md_ctx)
        )
      end)

      it('handles unknown options', function()
        assert.are.equal(
          'pandoc: Unknown option --bogus-flag.',
          get_provider().failure_summary(pandoc_result('pandoc_unknown_opt.txt'), md_ctx)
        )
      end)

      it('preserves long invalid pdf-engine messages', function()
        assert.are.equal(
          'pandoc: ' .. helpers.read_fixture('pandoc_pdf_engine.txt'),
          get_provider().failure_summary(pandoc_result('pandoc_pdf_engine.txt'), md_ctx)
        )
      end)

      it('ignores leading warnings before pandoc IO errors', function()
        local summary =
          get_provider().failure_summary(pandoc_result('pandoc_warning_then_io_error.txt'), md_ctx)
        assert.are.equal(
          'pandoc: /tmp/preview.nvim/audits/markdown: withBinaryFile: inappropriate type (is a directory)',
          summary
        )
        assert.is_nil(summary:find('[WARNING]', 1, true))
      end)

      it('returns nil for warning-only output', function()
        assert.is_nil(
          get_provider().failure_summary(pandoc_result('pandoc_warning_only.txt'), md_ctx)
        )
      end)

      it('returns nil when no shape matches', function()
        assert.is_nil(get_provider().failure_summary({ output = '' }, md_ctx))
        assert.is_nil(
          get_provider().failure_summary({ output = 'random unrelated text\n' }, md_ctx)
        )
      end)
    end)
  end

  local function define_github_failure_summary_tests(md_ctx)
    describe('failure_summary', function()
      it('summarizes YAML mapping errors', function()
        assert.are.equal(
          'YAML metadata: mapping values are not allowed in this context',
          presets.github.failure_summary(pandoc_result('pandoc_gfm_yaml_mapping.txt'), md_ctx)
        )
      end)

      it('walks YAML blocks past while context', function()
        assert.are.equal(
          "YAML metadata: did not find expected ',' or ']'",
          presets.github.failure_summary(pandoc_result('pandoc_gfm_yaml_flow.txt'), md_ctx)
        )
      end)

      it('skips trailing Consider hints in YAML blocks', function()
        assert.are.equal(
          'YAML metadata: did not find expected key',
          presets.github.failure_summary(pandoc_result('pandoc_gfm_yaml_block.txt'), md_ctx)
        )
      end)

      it('summarizes YAML alias errors', function()
        assert.are.equal(
          'YAML metadata: Unknown alias `undefined_anchor`',
          presets.github.failure_summary(pandoc_result('pandoc_gfm_yaml_alias.txt'), md_ctx)
        )
      end)

      it('handles Error at failures with filename context', function()
        local result = {
          code = 1,
          stdout = '',
          stderr = 'Error at "document.md" (line 12, column 5): unexpected "}" expecting letter',
          output = 'Error at "document.md" (line 12, column 5): unexpected "}" expecting letter',
        }
        assert.are.equal(
          'document.md: unexpected "}" expecting letter',
          presets.github.failure_summary(result, md_ctx)
        )
      end)

      it('summarizes pandoc IO errors without HasCallStack noise', function()
        local summary =
          presets.github.failure_summary(pandoc_result('pandoc_gfm_input_missing.txt'), md_ctx)
        assert.are.equal(
          '/tmp/preview.nvim/audits/github/repro/__nonexistent.md: withBinaryFile: does not exist (No such file or directory)',
          summary
        )
        assert.is_nil(summary:find('HasCallStack', 1, true))
        assert.is_nil(summary:find('Exception.hs', 1, true))
      end)

      it('summarizes template-missing errors', function()
        assert.are.equal(
          helpers.read_fixture('pandoc_gfm_template_missing.txt'),
          presets.github.failure_summary(pandoc_result('pandoc_gfm_template_missing.txt'), md_ctx)
        )
      end)

      it('summarizes unknown option errors', function()
        assert.are.equal(
          'Unknown option --bad-flag-does-not-exist.',
          presets.github.failure_summary(pandoc_result('pandoc_gfm_unknown_option.txt'), md_ctx)
        )
      end)

      it('summarizes unsupported extension errors', function()
        assert.are.equal(
          'The extension nonexistent_extension is not supported for gfm.',
          presets.github.failure_summary(pandoc_result('pandoc_gfm_bad_extension.txt'), md_ctx)
        )
      end)

      it('returns nil for empty output', function()
        assert.is_nil(presets.github.failure_summary({ output = '' }, md_ctx))
      end)

      it('returns nil when output matches no known pattern', function()
        assert.is_nil(
          presets.github.failure_summary({ output = 'random unrelated text\n' }, md_ctx)
        )
      end)
    end)
  end

  describe('typst', function()
    local function typst_result(path, code)
      local output = helpers.read_fixture(path)
      return { code = code or 1, stdout = '', stderr = output, output = output }
    end

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

    it('returns clean command', function()
      assert.are.same({ 'rm', '-f', '/tmp/document.pdf' }, presets.typst.clean(ctx))
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
      assert.are.equal('--diagnostic-format', result[3])
      assert.are.equal('short', result[4])
      assert.are.equal(ctx.file, result[5])
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

    it('parses fixture output', function()
      local diagnostics = presets.typst.error_parser(helpers.read_fixture('typst.txt'), ctx)
      assert.are.equal(2, #diagnostics)
      assert.are.equal('unexpected token', diagnostics[1].message)
      assert.are.equal('unused variable', diagnostics[2].message)
    end)

    describe('failure_summary', function()
      it('returns the message for a single error', function()
        local result = {
          code = 1,
          stdout = '',
          stderr = 'main.typ:3:12: error: expected expression',
          output = 'main.typ:3:12: error: expected expression',
        }
        assert.are.equal('expected expression', presets.typst.failure_summary(result, ctx))
      end)

      it('returns the first error message when multiple errors are present', function()
        assert.are.equal(
          'expected expression',
          presets.typst.failure_summary(typst_result('typst_multiple_errors.txt'), ctx)
        )
      end)

      it('preserves messages containing colons and quoted text', function()
        assert.are.equal(
          'panicked with: "something went terribly wrong"',
          presets.typst.failure_summary(typst_result('typst_panic.txt'), ctx)
        )
      end)

      it('preserves file not found messages', function()
        assert.are.equal(
          'file not found (searched at /tmp/preview.nvim/audits/typst/repro/does_not_exist.png)',
          presets.typst.failure_summary(typst_result('typst_missing_file.txt'), ctx)
        )
      end)

      it('preserves long messages without truncation', function()
        assert.are.equal(
          'unknown variable: nonexistent_very_long_function_name_for_demonstrating_potentially_wrapping_diagnostic_output_lines',
          presets.typst.failure_summary(typst_result('typst_long_message.txt'), ctx)
        )
      end)

      it('skips watch-mode boilerplate and picks the first error', function()
        local summary =
          presets.typst.failure_summary(typst_result('typst_watch_first_fail.txt'), ctx)
        assert.are.equal('expected expression', summary)
        assert.is_nil(summary:find('watching ', 1, true))
        assert.is_nil(summary:find('writing to ', 1, true))
        assert.is_nil(summary:find('compiled with errors', 1, true))
        assert.is_nil(summary:find('compiling ...', 1, true))
      end)

      it('returns nil for warning-only output', function()
        assert.is_nil(presets.typst.failure_summary(typst_result('typst_warning_only.txt'), ctx))
      end)

      it('returns nil for CLI input-not-found output', function()
        assert.is_nil(presets.typst.failure_summary(typst_result('typst_cli_no_input.txt'), ctx))
      end)

      it('returns nil for CLI argument parsing output', function()
        assert.is_nil(presets.typst.failure_summary(typst_result('typst_cli_bad_flag.txt'), ctx))
      end)

      it('returns nil for empty output', function()
        local result = { code = 1, stdout = '', stderr = '', output = '' }
        assert.is_nil(presets.typst.failure_summary(result, ctx))
      end)
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

    it('summarizes file-line-error format from output', function()
      local output = table.concat({
        './document.tex:10: Undefined control sequence.',
        'l.10 \\badcommand',
        'Collected error summary (may duplicate other messages):',
        "  pdflatex: Command for 'pdflatex' gave return code 256",
      }, '\n')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        'document.tex:10: Undefined control sequence.',
        presets.latex.failure_summary(result, tex_ctx)
      )
    end)

    it('summarizes file-line-error format with spaces in the path', function()
      local output = './my docs/document.tex:10: Undefined control sequence.'
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        'document.tex:10: Undefined control sequence.',
        presets.latex.failure_summary(result, tex_ctx)
      )
    end)

    it('prefers ! LaTeX Error over later cascading file-line errors', function()
      local output = table.concat({
        "! LaTeX Error: File `enumitem.sty' not found.",
        './document.tex:3: Emergency stop.',
        './document.tex:3:  ==> Fatal error occurred, no output PDF file produced!',
        "  pdflatex: Command for 'pdflatex' gave return code 1",
      }, '\n')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        "LaTeX Error: File `enumitem.sty' not found.",
        presets.latex.failure_summary(result, tex_ctx)
      )
    end)

    it('skips ==> continuation lines in both formats', function()
      local output = table.concat({
        './document.tex:3:  ==> Fatal error occurred',
        '!  ==> Fatal error occurred, no output PDF file produced!',
        '! Emergency stop.',
      }, '\n')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal('Emergency stop.', presets.latex.failure_summary(result, tex_ctx))
    end)

    it('falls back to the first ! line when there is no file-line error', function()
      local output = table.concat({
        'Runaway argument?',
        '! File ended while scanning use of \\@fileswith@ptions.',
        '! Emergency stop.',
        '!  ==> Fatal error occurred, no output PDF file produced!',
      }, '\n')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        'File ended while scanning use of \\@fileswith@ptions.',
        presets.latex.failure_summary(result, tex_ctx)
      )
    end)

    it('returns nil for boilerplate-only output', function()
      local output = table.concat({
        'Latexmk: Errors, so I did not complete making targets',
        'Collected error summary (may duplicate other messages):',
        "  pdflatex: Command for 'pdflatex' gave return code 1",
      }, '\n')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.is_nil(presets.latex.failure_summary(result, tex_ctx))
    end)

    it('returns nil for successful fixture output', function()
      local output = helpers.read_fixture('latexmk_positive.txt')
      local result = { code = 0, stdout = output, stderr = '', output = output }
      assert.is_nil(presets.latex.failure_summary(result, tex_ctx))
    end)

    it('returns nil for empty output', function()
      local result = { code = 12, stdout = '', stderr = '', output = '' }
      assert.is_nil(presets.latex.failure_summary(result, tex_ctx))
    end)

    it('summarizes undefined control sequence fixture output', function()
      local output = helpers.read_fixture('latexmk_undefined_cs.txt')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        'document.tex:4: Undefined control sequence.',
        presets.latex.failure_summary(result, tex_ctx)
      )
    end)

    it('summarizes missing package fixture output', function()
      local output = helpers.read_fixture('latexmk_missing_pkg.txt')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        "LaTeX Error: File `definitelymissingpackage.sty' not found.",
        presets.latex.failure_summary(result, tex_ctx)
      )
    end)

    it('summarizes noisy multi-error fixture output', function()
      local output = helpers.read_fixture('latexmk_noisy_multi.txt')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        'document.tex:4: Undefined control sequence.',
        presets.latex.failure_summary(result, tex_ctx)
      )
    end)

    it('summarizes emergency stop fixture output', function()
      local output = helpers.read_fixture('latexmk_emergency_stop.txt')
      local result = { code = 12, stdout = output, stderr = '', output = output }
      assert.are.equal(
        'File ended while scanning use of \\@fileswith@ptions.',
        presets.latex.failure_summary(result, tex_ctx)
      )
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

    it('parses fixture output', function()
      local diagnostics = presets.latex.error_parser(helpers.read_fixture('latexmk.txt'), tex_ctx)
      assert.are.equal(2, #diagnostics)
      assert.are.equal('Undefined control sequence.', diagnostics[1].message)
      assert.are.equal(
        "pdflatex: Command for 'pdflatex' gave return code 256",
        diagnostics[2].message
      )
    end)

    it('returns empty table for clean stderr', function()
      local diagnostics = presets.latex.error_parser('', tex_ctx)
      assert.are.same({}, diagnostics)
    end)
  end)

  describe('pdflatex', function()
    local tex_ctx = {
      bufnr = 1,
      file = '/tmp/document.tex',
      root = '/tmp',
      ft = 'tex',
    }

    local function pdflatex_result(path, code)
      local output = helpers.read_fixture(path)
      return { code = code or 1, stdout = output, stderr = '', output = output }
    end

    it('has ft', function()
      assert.are.equal('tex', presets.pdflatex.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'pdflatex' }, presets.pdflatex.cmd)
    end)

    it('returns args with flags and file path', function()
      local args = presets.pdflatex.args(tex_ctx)
      assert.are.same(
        { '-interaction=nonstopmode', '-file-line-error', '-synctex=1', '/tmp/document.tex' },
        args
      )
    end)

    it('returns pdf output path', function()
      assert.are.equal('/tmp/document.pdf', presets.pdflatex.output(tex_ctx))
    end)

    it('has open enabled', function()
      assert.is_true(presets.pdflatex.open)
    end)

    it('returns clean command removing pdf and aux files', function()
      local clean = presets.pdflatex.clean(tex_ctx)
      assert.are.same({
        'rm',
        '-f',
        '/tmp/document.pdf',
        '/tmp/document.aux',
        '/tmp/document.log',
        '/tmp/document.synctex.gz',
      }, clean)
    end)

    it('has no reload', function()
      assert.is_nil(presets.pdflatex.reload)
    end)

    it('sets max_print_line env for stable failure summaries', function()
      assert.are.same({ max_print_line = '10000' }, presets.pdflatex.env)
    end)

    describe('failure_summary', function()
      it('prefers LaTeX Error for missing package fixture output', function()
        assert.are.equal(
          "LaTeX Error: File `definitelymissingpackage.sty' not found.",
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_missing_package.txt'), tex_ctx)
        )
      end)

      it('uses the first non-noise ! line for missing brace fixture output', function()
        assert.are.equal(
          'File ended while scanning use of \\textbf .',
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_missing_brace.txt'), tex_ctx)
        )
      end)

      it('uses the file-line message for undefined control sequence fixture output', function()
        assert.are.equal(
          'Undefined control sequence.',
          presets.pdflatex.failure_summary(
            pdflatex_result('pdflatex_undefined_cs_full.txt'),
            tex_ctx
          )
        )
      end)

      it('uses the first non-noise file-line message for missing dollar fixture output', function()
        assert.are.equal(
          'Missing $ inserted.',
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_missing_dollar.txt'), tex_ctx)
        )
      end)

      it('prefers LaTeX Error for missing file fixture output', function()
        assert.are.equal(
          "LaTeX Error: File `nonexistent_file_xyz.tex' not found.",
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_file_not_found.txt'), tex_ctx)
        )
      end)

      it('ignores l.n continuations in long message fixture output', function()
        assert.are.equal(
          'Undefined control sequence.',
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_long_message.txt'), tex_ctx)
        )
      end)

      it('uses file-line LaTeX Error for missing document environment fixture output', function()
        assert.are.equal(
          'LaTeX Error: Missing \\begin{document}.',
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_missing_doc_env.txt'), tex_ctx)
        )
      end)

      it('uses the first file-line LaTeX Error in syntax-only fixture output', function()
        assert.are.equal(
          'LaTeX Error: \\begin{document} ended by \\end{itemize}.',
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_syntax_only.txt'), tex_ctx)
        )
      end)

      it('summarizes unwrapped long file-line message fixture output', function()
        assert.are.equal(
          'This is an intentionally extremely long error message designed to make pdflatex wrap the output onto multiple lines for testing purposes.',
          presets.pdflatex.failure_summary(
            pdflatex_result('pdflatex_wrapped_error_unwrapped.txt'),
            tex_ctx
          )
        )
      end)

      it('summarizes unwrapped LaTeX Error fixture output', function()
        assert.are.equal(
          "LaTeX Error: File `aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.sty' not found.",
          presets.pdflatex.failure_summary(
            pdflatex_result('pdflatex_wrapped_latex_error_unwrapped.txt'),
            tex_ctx
          )
        )
      end)

      it('returns nil for emergency-only fixture output', function()
        assert.is_nil(
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_emergency_only.txt'), tex_ctx)
        )
      end)

      it('returns nil for successful fixture output', function()
        assert.is_nil(
          presets.pdflatex.failure_summary(pdflatex_result('pdflatex_valid.txt', 0), tex_ctx)
        )
      end)

      it('returns nil for empty output', function()
        assert.is_nil(presets.pdflatex.failure_summary({ output = '' }, tex_ctx))
      end)

      it('does not pick Emergency stop when a later file-line error exists', function()
        local output = table.concat({
          './document.tex:3: Emergency stop.',
          './document.tex:5: Missing $ inserted.',
        }, '\n')
        local result = { code = 1, stdout = output, stderr = '', output = output }
        assert.are.equal('Missing $ inserted.', presets.pdflatex.failure_summary(result, tex_ctx))
      end)

      it('skips fatal continuation lines in both file-line and ! forms', function()
        local output = table.concat({
          './document.tex:3:  ==> Fatal error occurred, no output PDF file produced!',
          '!  ==> Fatal error occurred, no output PDF file produced!',
          '! Emergency stop.',
        }, '\n')
        local result = { code = 1, stdout = output, stderr = '', output = output }
        assert.is_nil(presets.pdflatex.failure_summary(result, tex_ctx))
      end)
    end)

    it('parses file-line-error format', function()
      local output = './document.tex:10: Undefined control sequence.'
      local diagnostics = presets.pdflatex.error_parser(output, tex_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(9, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('Undefined control sequence.', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    end)

    it('parses fixture output', function()
      local diagnostics =
        presets.pdflatex.error_parser(helpers.read_fixture('pdflatex.txt'), tex_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal('Undefined control sequence.', diagnostics[1].message)
    end)

    it('returns empty table for clean output', function()
      assert.are.same({}, presets.pdflatex.error_parser('', tex_ctx))
    end)
  end)

  describe('tectonic', function()
    local tex_ctx = {
      bufnr = 1,
      file = '/tmp/document.tex',
      root = '/tmp',
      ft = 'tex',
    }

    local function tectonic_stderr_result(path, code)
      local stderr = helpers.read_fixture(path)
      return { code = code or 1, stdout = '', stderr = stderr, output = stderr }
    end

    it('has ft', function()
      assert.are.equal('tex', presets.tectonic.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'tectonic' }, presets.tectonic.cmd)
    end)

    it('returns args with file path', function()
      assert.are.same({ '/tmp/document.tex' }, presets.tectonic.args(tex_ctx))
    end)

    it('returns pdf output path', function()
      assert.are.equal('/tmp/document.pdf', presets.tectonic.output(tex_ctx))
    end)

    it('has open enabled', function()
      assert.is_true(presets.tectonic.open)
    end)

    it('returns clean command removing pdf', function()
      assert.are.same({ 'rm', '-f', '/tmp/document.pdf' }, presets.tectonic.clean(tex_ctx))
    end)

    it('has no reload', function()
      assert.is_nil(presets.tectonic.reload)
    end)

    it('returns nil failure summary for success output', function()
      local stdout = helpers.read_fixture('tectonic_valid.txt')
      local result = { code = 0, stdout = stdout, stderr = '', output = stdout }
      assert.is_nil(presets.tectonic.failure_summary(result, tex_ctx))
    end)

    it('summarizes missing dollar fixture output', function()
      assert.are.equal(
        'missing_dollar.tex:5: Missing $ inserted',
        presets.tectonic.failure_summary(tectonic_stderr_result('tectonic.txt'), tex_ctx)
      )
    end)

    it('summarizes multi-error fixture output with the first error', function()
      assert.are.equal(
        'multi_error.tex:3: Undefined control sequence',
        presets.tectonic.failure_summary(
          tectonic_stderr_result('tectonic_multi_error.txt'),
          tex_ctx
        )
      )
    end)

    it('summarizes missing package fixture output', function()
      assert.are.equal(
        "missing_package.tex:3: LaTeX Error: File `this-package-definitely-does-not-exist.sty' not found.",
        presets.tectonic.failure_summary(
          tectonic_stderr_result('tectonic_missing_package.txt'),
          tex_ctx
        )
      )
    end)

    it('summarizes missing input fixture output', function()
      assert.are.equal(
        "missing_input.tex:3: LaTeX Error: File `nonexistent-file-xyz.tex' not found.",
        presets.tectonic.failure_summary(
          tectonic_stderr_result('tectonic_missing_input.txt'),
          tex_ctx
        )
      )
    end)

    it('summarizes missing image fixture output', function()
      assert.are.equal(
        "missing_image.tex:4: Unable to load picture or PDF file 'nonexistent-image.png'",
        presets.tectonic.failure_summary(
          tectonic_stderr_result('tectonic_missing_image.txt'),
          tex_ctx
        )
      )
    end)

    it('skips continuation lines around wrapped long message fixture output', function()
      assert.are.equal(
        'wrapped_long_msg.tex:6: LaTeX Error: \\begin{equation} on input line 4 ended by \\end{equationoops}.',
        presets.tectonic.failure_summary(
          tectonic_stderr_result('tectonic_wrapped_long_msg.txt'),
          tex_ctx
        )
      )
    end)

    it('strips leading ! for missing brace fixture output', function()
      assert.are.equal(
        'File ended while scanning use of \\textbf',
        presets.tectonic.failure_summary(
          tectonic_stderr_result('tectonic_missing_brace.txt'),
          tex_ctx
        )
      )
    end)

    it('returns Emergency stop for empty fixture output', function()
      assert.are.equal(
        'Emergency stop',
        presets.tectonic.failure_summary(tectonic_stderr_result('tectonic_empty.txt'), tex_ctx)
      )
    end)

    it('returns nil when only the halted trailer is present', function()
      local result = {
        code = 1,
        stdout = '',
        stderr = 'error: halted on potentially-recoverable error as specified',
        output = 'error: halted on potentially-recoverable error as specified',
      }
      assert.is_nil(presets.tectonic.failure_summary(result, tex_ctx))
    end)

    it('parses real tectonic error format', function()
      local output = 'error: missing_dollar.tex:5: Missing $ inserted'
      local diagnostics = presets.tectonic.error_parser(output, tex_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(4, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('Missing $ inserted', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    end)

    it('parses fixture output', function()
      local diagnostics =
        presets.tectonic.error_parser(helpers.read_fixture('tectonic.txt'), tex_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal('Missing $ inserted', diagnostics[1].message)
    end)

    it('returns no diagnostics for missing brace fixture output', function()
      local diagnostics =
        presets.tectonic.error_parser(helpers.read_fixture('tectonic_missing_brace.txt'), tex_ctx)
      assert.are.same({}, diagnostics)
    end)

    it('returns empty table for clean output', function()
      assert.are.same({}, presets.tectonic.error_parser('', tex_ctx))
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

    it('returns args with standalone and katex flags', function()
      local args = presets.markdown.args(md_ctx)
      assert.is_table(args)
      assert.are.same({ '/tmp/document.md', '-s', '--katex', '-o', '/tmp/document.html' }, args)
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

    define_pandoc_failure_summary_tests(function()
      return presets.markdown
    end, md_ctx)

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

    it('parses fixture output', function()
      local diagnostics = presets.markdown.error_parser(helpers.read_fixture('pandoc.txt'), md_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal("did not find expected ',' or ']'", diagnostics[1].message)
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

    it('returns args with standalone, katex, and no-highlight flags', function()
      local args = presets.github.args(md_ctx)
      assert.is_table(args)
      assert.are.same({
        '-f',
        'gfm',
        '/tmp/document.md',
        '-s',
        '--katex',
        '--no-highlight',
        '-o',
        '/tmp/document.html',
        '--template',
        vim.api.nvim_get_runtime_file('lua/preview/templates/gfm.html', false)[1],
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

    define_github_failure_summary_tests(md_ctx)

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

    it('parses fixture output', function()
      local diagnostics = presets.github.error_parser(helpers.read_fixture('pandoc.txt'), md_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal("did not find expected ',' or ']'", diagnostics[1].message)
    end)

    it('parses YAML blocks past while and Consider lines', function()
      local diagnostics =
        presets.github.error_parser(helpers.read_fixture('pandoc_gfm_yaml_block.txt'), md_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal('did not find expected key', diagnostics[1].message)
    end)

    it('returns empty table for clean output', function()
      local diagnostics = presets.github.error_parser('', md_ctx)
      assert.are.same({}, diagnostics)
    end)
  end)

  describe('asciidoctor', function()
    local adoc_ctx = {
      bufnr = 1,
      file = '/tmp/document.adoc',
      root = '/tmp',
      ft = 'asciidoc',
      output = '/tmp/document.html',
    }

    it('has ft', function()
      assert.are.equal('asciidoc', presets.asciidoctor.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'asciidoctor' }, presets.asciidoctor.cmd)
    end)

    it('returns args with file and output', function()
      assert.are.same(
        { '--failure-level', 'ERROR', '/tmp/document.adoc', '-o', '/tmp/document.html' },
        presets.asciidoctor.args(adoc_ctx)
      )
    end)

    it('returns html output path', function()
      assert.are.equal('/tmp/document.html', presets.asciidoctor.output(adoc_ctx))
    end)

    it('returns clean command', function()
      assert.are.same({ 'rm', '-f', '/tmp/document.html' }, presets.asciidoctor.clean(adoc_ctx))
    end)

    it('has open enabled', function()
      assert.is_true(presets.asciidoctor.open)
    end)

    it('has reload enabled for SSE', function()
      assert.is_true(presets.asciidoctor.reload)
    end)

    describe('failure_summary', function()
      it('summarizes a single ERROR line', function()
        local output = 'asciidoctor: ERROR: doc.adoc: line 5: include file not found: /tmp/a.adoc\n'
        assert.are.equal(
          'doc.adoc: line 5: include file not found: /tmp/a.adoc',
          presets.asciidoctor.failure_summary({ output = output }, adoc_ctx)
        )
      end)

      it('skips WARNING when an ERROR is present', function()
        local output = helpers.read_fixture('asciidoctor_error_with_warning.txt')
        assert.are.equal(
          'mixed_err_warn.adoc: line 7: include file not found: /tmp/preview.nvim/audits/asciidoctor/repro/missing.adoc',
          presets.asciidoctor.failure_summary({ output = output }, adoc_ctx)
        )
      end)

      it('returns the first ERROR when many are present', function()
        local output = helpers.read_fixture('asciidoctor_multi_error.txt')
        assert.are.equal(
          'multiple_errors.adoc: line 3: include file not found: /tmp/preview.nvim/audits/asciidoctor/repro/missing_a.adoc',
          presets.asciidoctor.failure_summary({ output = output }, adoc_ctx)
        )
      end)

      it('summarizes FAILED form', function()
        local output = helpers.read_fixture('asciidoctor_failed.txt')
        assert.are.equal(
          'input file /tmp/nonexistent-asciidoc-input.adoc is missing',
          presets.asciidoctor.failure_summary({ output = output }, adoc_ctx)
        )
      end)

      it('summarizes invalid option even when usage precedes it', function()
        local output = helpers.read_fixture('asciidoctor_invalid_option.txt')
        assert.are.equal(
          'invalid option: --bogus-option',
          presets.asciidoctor.failure_summary({ output = output }, adoc_ctx)
        )
      end)

      it('falls back to nil for Ruby stack traces without anchored asciidoctor lines', function()
        local output = helpers.read_fixture('asciidoctor_trace.txt')
        assert.is_nil(presets.asciidoctor.failure_summary({ output = output }, adoc_ctx))
      end)

      it('falls back to nil on empty output', function()
        assert.is_nil(presets.asciidoctor.failure_summary({ output = '' }, adoc_ctx))
      end)

      it('summarizes WARNING when it is the only available severity', function()
        local output = helpers.read_fixture('asciidoctor_warning_only.txt')
        assert.are.equal(
          'warning_only.adoc: line 8: section title out of sequence: expected level 2, got level 3',
          presets.asciidoctor.failure_summary({ output = output }, adoc_ctx)
        )
      end)
    end)

    it('parses error messages', function()
      local output =
        'asciidoctor: ERROR: document.adoc: line 8: invalid part, must have at least one section'
      local diagnostics = presets.asciidoctor.error_parser(output, adoc_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(7, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal('invalid part, must have at least one section', diagnostics[1].message)
      assert.are.equal(vim.diagnostic.severity.ERROR, diagnostics[1].severity)
    end)

    it('parses warning messages', function()
      local output = 'asciidoctor: WARNING: document.adoc: line 52: section title out of sequence'
      local diagnostics = presets.asciidoctor.error_parser(output, adoc_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(51, diagnostics[1].lnum)
      assert.are.equal(vim.diagnostic.severity.WARN, diagnostics[1].severity)
    end)

    it('parses fixture output', function()
      local diagnostics =
        presets.asciidoctor.error_parser(helpers.read_fixture('asciidoctor.txt'), adoc_ctx)
      assert.are.equal(2, #diagnostics)
      assert.are.equal('unmatched macro', diagnostics[1].message)
      assert.are.equal('section title out of sequence', diagnostics[2].message)
    end)

    it('returns empty table for clean output', function()
      assert.are.same({}, presets.asciidoctor.error_parser('', adoc_ctx))
    end)
  end)

  describe('plantuml', function()
    local puml_ctx = {
      bufnr = 1,
      file = '/tmp/document.puml',
      root = '/tmp',
      ft = 'plantuml',
      output = '/tmp/document.svg',
    }

    it('has ft', function()
      assert.are.equal('plantuml', presets.plantuml.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'plantuml' }, presets.plantuml.cmd)
    end)

    it('returns args with svg flag and file path', function()
      assert.are.same({ '-tsvg', '/tmp/document.puml' }, presets.plantuml.args(puml_ctx))
    end)

    it('returns svg output path', function()
      assert.are.equal('/tmp/document.svg', presets.plantuml.output(puml_ctx))
    end)

    it('returns clean command', function()
      assert.are.same({ 'rm', '-f', '/tmp/document.svg' }, presets.plantuml.clean(puml_ctx))
    end)

    it('has open enabled', function()
      assert.is_true(presets.plantuml.open)
    end)

    it('parses fixture output', function()
      local diagnostics =
        presets.plantuml.error_parser(helpers.read_fixture('plantuml.txt'), puml_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(3, diagnostics[1].lnum)
      assert.are.equal('Error line 4 in file: /tmp/document.puml', diagnostics[1].message)
    end)
  end)

  describe('mermaid', function()
    local mmd_ctx = {
      bufnr = 1,
      file = '/tmp/document.mmd',
      root = '/tmp',
      ft = 'mermaid',
      output = '/tmp/document.svg',
    }

    it('has ft', function()
      assert.are.equal('mermaid', presets.mermaid.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'mmdc' }, presets.mermaid.cmd)
    end)

    it('returns args with input and output', function()
      assert.are.same(
        { '-i', '/tmp/document.mmd', '-o', '/tmp/document.svg' },
        presets.mermaid.args(mmd_ctx)
      )
    end)

    it('returns svg output path', function()
      assert.are.equal('/tmp/document.svg', presets.mermaid.output(mmd_ctx))
    end)

    it('returns clean command', function()
      assert.are.same({ 'rm', '-f', '/tmp/document.svg' }, presets.mermaid.clean(mmd_ctx))
    end)

    it('has open enabled', function()
      assert.is_true(presets.mermaid.open)
    end)

    it('parses fixture output', function()
      local diagnostics = presets.mermaid.error_parser(helpers.read_fixture('mermaid.txt'), mmd_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(2, diagnostics[1].lnum)
      assert.is_truthy(diagnostics[1].message:find('Expecting', 1, true))
    end)
  end)

  describe('quarto', function()
    local qmd_ctx = {
      bufnr = 1,
      file = '/tmp/document.qmd',
      root = '/tmp',
      ft = 'quarto',
      output = '/tmp/document.html',
    }

    local function quarto_summary(path, code)
      return presets.quarto.failure_summary(pandoc_result(path, code), qmd_ctx)
    end

    it('has ft', function()
      assert.are.equal('quarto', presets.quarto.ft)
    end)

    it('has cmd', function()
      assert.are.same({ 'quarto' }, presets.quarto.cmd)
    end)

    it('returns args with render subcommand and html format', function()
      assert.are.same(
        { 'render', '/tmp/document.qmd', '--to', 'html', '--embed-resources' },
        presets.quarto.args(qmd_ctx)
      )
    end)

    it('returns html output path', function()
      assert.are.equal('/tmp/document.html', presets.quarto.output(qmd_ctx))
    end)

    it('returns clean command removing html and _files directory', function()
      assert.are.same(
        { 'rm', '-rf', '/tmp/document.html', '/tmp/document_files' },
        presets.quarto.clean(qmd_ctx)
      )
    end)

    it('has open enabled', function()
      assert.is_true(presets.quarto.open)
    end)

    it('has reload enabled for SSE', function()
      assert.is_true(presets.quarto.reload)
    end)

    describe('failure_summary', function()
      it('summarizes YAMLException with location', function()
        assert.are.equal(
          'YAMLException: missed comma between flow collection entries (3:1)',
          quarto_summary('quarto.txt')
        )
      end)

      it('summarizes unknown render formats', function()
        assert.are.equal(
          'Unknown format thisformatdoesnotexist',
          quarto_summary('quarto_unknown_format.txt')
        )
      end)

      it('summarizes missing input files', function()
        assert.are.equal(
          'No valid input files passed to render',
          quarto_summary('quarto_missing_input.txt')
        )
      end)

      it('returns nil for YAML validation wrapper output', function()
        assert.is_nil(quarto_summary('quarto_yaml_validation.txt'))
      end)

      it('returns nil for pandoc-routed filter errors', function()
        assert.is_nil(quarto_summary('quarto_filter_missing.txt'))
      end)

      it('returns nil for python tracebacks', function()
        assert.is_nil(quarto_summary('quarto_python_traceback.txt'))
      end)

      it('returns nil for success output', function()
        assert.is_nil(quarto_summary('quarto_success.txt', 0))
      end)
    end)

    it('parses fixture output', function()
      local diagnostics = presets.quarto.error_parser(helpers.read_fixture('quarto.txt'), qmd_ctx)
      assert.are.equal(1, #diagnostics)
      assert.are.equal(2, diagnostics[1].lnum)
      assert.are.equal(0, diagnostics[1].col)
      assert.are.equal(
        'YAMLException: missed comma between flow collection entries',
        diagnostics[1].message
      )
    end)
  end)
end)
