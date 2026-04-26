local helpers = require('spec.helpers')

describe('compiler', function()
  local compiler

  before_each(function()
    helpers.reset_config()
    compiler = require('preview.compiler')
  end)

  local function process_done(bufnr)
    local s = compiler._test.state[bufnr]
    return not s or s.process == nil
  end

  describe('compile', function()
    it('spawns a process and tracks it in state', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test.txt')
      vim.bo[bufnr].modified = false

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'echo', provider, ctx)
      local s = compiler._test.state[bufnr]
      assert.is_not_nil(s)
      assert.is_not_nil(s.process)
      assert.are.equal('echo', s.provider)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      assert.is_nil(compiler._test.state[bufnr].process)
      helpers.delete_buffer(bufnr)
    end)

    it('fires PreviewCompileStarted event', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_event.txt')
      vim.bo[bufnr].modified = false

      local fired = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'PreviewCompileStarted',
        once = true,
        callback = function()
          fired = true
        end,
      })

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg)
        if msg:find('compiling') then
          notified = true
        end
      end

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_event.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'echo', provider, ctx)
      vim.notify = orig
      assert.is_true(fired)
      assert.is_true(notified)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      helpers.delete_buffer(bufnr)
    end)

    it('fires PreviewCompileSuccess on exit code 0', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_success.txt')
      vim.bo[bufnr].modified = false

      local succeeded = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'PreviewCompileSuccess',
        once = true,
        callback = function()
          succeeded = true
        end,
      })

      local provider = { cmd = { 'true' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_success.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'truecmd', provider, ctx)

      vim.wait(2000, function()
        return succeeded
      end, 50)

      assert.is_true(succeeded)
      helpers.delete_buffer(bufnr)
    end)

    it('notifies and returns when binary is not executable', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_nobin.txt')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg)
        if msg:find('not executable') then
          notified = true
        end
      end

      local provider = { cmd = { 'totally_nonexistent_binary_xyz_preview' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_nobin.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'nobin', provider, ctx)
      vim.notify = orig

      assert.is_true(notified)
      assert.is_true(process_done(bufnr))
      helpers.delete_buffer(bufnr)
    end)

    it('fires PreviewCompileFailed on non-zero exit', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail.txt')
      vim.bo[bufnr].modified = false

      local failed = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'PreviewCompileFailed',
        once = true,
        callback = function()
          failed = true
        end,
      })

      local provider = { cmd = { 'false' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return failed
      end, 50)

      assert.is_true(failed)
      helpers.delete_buffer(bufnr)
    end)

    it('notifies generically on compile failure when structured errors exist', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_summary.txt')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: compilation failed' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[cat >&2 <<'EOF'
/tmp/preview_test_fail_summary.txt:6: Emergenc
y stop.
! LaTeX Error: File `enumitem.sty' not found.
EOF
exit 12]],
        },
        error_parser = function()
          return {
            { lnum = 5, col = 0, message = 'Emergenc', severity = vim.diagnostic.severity.ERROR },
          }
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_summary.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      helpers.delete_buffer(bufnr)
    end)

    it('hints :Preview output when compile failure has no structured errors', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_output_hint.txt')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: compilation failed (see :Preview output)' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'fatal compiler output' >&2
exit 12]],
        },
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_output_hint.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      helpers.delete_buffer(bufnr)
    end)

    it('uses provider failure summary on compile failure', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_custom_summary.txt')
      vim.bo[bufnr].modified = false

      local notified = false
      local captured = {}
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: bad input' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'error: bad input' >&2
exit 12]],
        },
        error_parser = function()
          return {
            {
              lnum = 0,
              col = 0,
              message = 'diagnostic error',
              severity = vim.diagnostic.severity.ERROR,
            },
          }
        end,
        failure_summary = function(result, ctx)
          captured.code = result.code
          captured.output = result.output
          captured.file = ctx.file
          captured.output_file = ctx.output
          return 'bad input'
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_custom_summary.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      assert.are.equal(12, captured.code)
      assert.are.equal('/tmp/preview_test_fail_custom_summary.txt', captured.file)
      assert.are.equal('', captured.output_file)
      assert.is_truthy(captured.output:find('bad input', 1, true))
      helpers.delete_buffer(bufnr)
    end)

    it('uses typst failure summary on compile failure', function()
      local presets = require('preview.presets')
      local bufnr = helpers.create_buffer({ 'hello' }, 'typst')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_typst_summary.typ')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: expected expression' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'main.typ:3:12: error: expected expression' >&2
exit 1]],
        },
        error_parser = presets.typst.error_parser,
        failure_summary = presets.typst.failure_summary,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_typst_summary.typ',
        root = '/tmp',
        ft = 'typst',
      }

      compiler.compile(bufnr, 'typst', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      helpers.delete_buffer(bufnr)
    end)

    it('uses tectonic failure summary on compile failure', function()
      local presets = require('preview.presets')
      local bufnr = helpers.create_buffer({ 'hello' }, 'tex')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_tectonic_summary.tex')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: missing_dollar.tex:5: Missing $ inserted' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'error: missing_dollar.tex:5: Missing $ inserted' >&2
printf '%s\n' 'error: halted on potentially-recoverable error as specified' >&2
exit 1]],
        },
        error_parser = presets.tectonic.error_parser,
        failure_summary = presets.tectonic.failure_summary,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_tectonic_summary.tex',
        root = '/tmp',
        ft = 'tex',
      }

      compiler.compile(bufnr, 'tectonic', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      helpers.delete_buffer(bufnr)
    end)

    it('uses markdown failure summary on compile failure without diagnostics', function()
      local presets = require('preview.presets')
      local bufnr = helpers.create_buffer({ '# hello' }, 'markdown')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_markdown_summary.md')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: pandoc: Unknown option --bogus-flag.' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = vim.tbl_extend('force', {}, presets.markdown, {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'Unknown option --bogus-flag.' >&2
printf '%s\n' 'Try pandoc --help for more information.' >&2
exit 6]],
        },
      })
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_markdown_summary.md',
        root = '/tmp',
        ft = 'markdown',
        output = '/tmp/preview_test_fail_markdown_summary.html',
      }

      compiler.compile(bufnr, 'markdown', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      helpers.delete_buffer(bufnr)
    end)

    it('uses github failure summary on compile failure with diagnostics', function()
      local presets = require('preview.presets')
      local bufnr = helpers.create_buffer({ '# hello' }, 'markdown')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_github_summary.md')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if
          msg == '[preview.nvim]: YAML metadata: mapping values are not allowed in this context'
        then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = vim.tbl_extend('force', {}, presets.github, {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'Error parsing YAML metadata at "/tmp/preview_test_fail_github_summary.md" (line 1, column 1):' >&2
printf '%s\n' 'YAML parse exception at line 2, column 6:' >&2
printf '%s\n' 'mapping values are not allowed in this context' >&2
exit 64]],
        },
      })
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_github_summary.md',
        root = '/tmp',
        ft = 'markdown',
        output = '/tmp/preview_test_fail_github_summary.html',
      }

      compiler.compile(bufnr, 'markdown', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      local diagnostics = vim.diagnostic.get(bufnr)
      assert.is_true(notified)
      assert.are.equal(1, #diagnostics)
      assert.are.equal('mapping values are not allowed in this context', diagnostics[1].message)
      assert.is_truthy(
        compiler
          .result(bufnr).output
          :find('mapping values are not allowed in this context', 1, true)
      )
      helpers.delete_buffer(bufnr)
    end)

    it('falls back when provider failure summary returns nil', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_nil_summary.txt')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: compilation failed (see :Preview output)' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'fatal compiler output' >&2
exit 12]],
        },
        failure_summary = function()
          return nil
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_nil_summary.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      helpers.delete_buffer(bufnr)
    end)

    it('falls back when provider failure summary errors', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_erroring_summary.txt')
      vim.bo[bufnr].modified = false

      local notified = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: compilation failed (see :Preview output)' then
          notified = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'fatal compiler output' >&2
exit 12]],
        },
        failure_summary = function()
          error('boom')
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_erroring_summary.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      vim.notify = orig
      assert.is_true(notified)
      helpers.delete_buffer(bufnr)
    end)

    it('stores full process output on failure', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_fail_result.txt')
      vim.bo[bufnr].modified = false

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'stdout line'
printf '%s\n' 'stderr line' >&2
exit 12]],
        },
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_fail_result.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      local result = compiler.result(bufnr)
      assert.are.equal(12, result.code)
      assert.is_truthy(result.stdout:find('stdout line', 1, true))
      assert.is_truthy(result.stderr:find('stderr line', 1, true))
      assert.is_truthy(result.output:find('stdout line', 1, true))
      assert.is_truthy(result.output:find('stderr line', 1, true))
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('errors mode', function()
    it('errors = false suppresses error parser', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_errors_false.txt')
      vim.bo[bufnr].modified = false

      local parser_called = false
      local provider = {
        cmd = { 'false' },
        errors = false,
        error_parser = function()
          parser_called = true
          return {}
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_errors_false.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'falsecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      assert.is_false(parser_called)
      helpers.delete_buffer(bufnr)
    end)

    it('errors = quickfix populates quickfix list', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_errors_qf.txt')
      vim.bo[bufnr].modified = false

      local provider = {
        cmd = { 'sh', '-c', 'echo "line 1 error" >&2; exit 1' },
        errors = 'quickfix',
        error_parser = function()
          return {
            { lnum = 0, col = 0, message = 'test error', severity = vim.diagnostic.severity.ERROR },
          }
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_errors_qf.txt',
        root = '/tmp',
        ft = 'text',
      }

      vim.fn.setqflist({}, 'r')
      compiler.compile(bufnr, 'qfcmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      local qflist = vim.fn.getqflist()
      assert.are.equal(1, #qflist)
      assert.are.equal('test error', qflist[1].text)
      assert.are.equal(1, qflist[1].lnum)

      vim.fn.setqflist({}, 'r')
      helpers.delete_buffer(bufnr)
    end)

    it('errors = quickfix clears quickfix on success', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_errors_qf_clear.txt')
      vim.bo[bufnr].modified = false

      vim.fn.setqflist({ { text = 'old error', lnum = 1 } }, 'r')
      assert.are.equal(1, #vim.fn.getqflist())

      local provider = {
        cmd = { 'true' },
        errors = 'quickfix',
        error_parser = function()
          return {}
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_errors_qf_clear.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'truecmd', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      assert.are.equal(0, #vim.fn.getqflist())
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('long-running notifications', function()
    it('notifies failure on stderr diagnostics', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_longrun.txt')
      vim.bo[bufnr].modified = false

      local notified_fail = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: compilation failed' and level == vim.log.levels.ERROR then
          notified_fail = true
        end
      end

      local provider = {
        cmd = { 'sh' },
        reload = function()
          return { 'sh', '-c', 'echo "error: bad input" >&2; sleep 60' }
        end,
        error_parser = function()
          return {
            { lnum = 0, col = 0, message = 'bad input', severity = vim.diagnostic.severity.ERROR },
          }
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_longrun.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'testprov', provider, ctx)

      vim.wait(3000, function()
        return notified_fail
      end, 50)

      vim.notify = orig
      assert.is_true(notified_fail)

      local s = compiler._test.state[bufnr]
      assert.is_true(s.has_errors)
      assert.is_truthy(compiler.result(bufnr).output:find('bad input', 1, true))

      compiler.stop(bufnr)
      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)
      helpers.delete_buffer(bufnr)
    end)

    it('uses provider failure summary for long-running failures', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_longrun_custom_summary.txt')
      vim.bo[bufnr].modified = false

      local notified_fail = false
      local captured = {}
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: bad input' and level == vim.log.levels.ERROR then
          notified_fail = true
        end
      end

      local provider = {
        cmd = { 'sh' },
        reload = function()
          return { 'sh', '-c', 'echo "error: bad input" >&2; sleep 60' }
        end,
        error_parser = function()
          return {
            {
              lnum = 0,
              col = 0,
              message = 'bad input',
              severity = vim.diagnostic.severity.ERROR,
            },
          }
        end,
        failure_summary = function(result, ctx)
          captured.code = result.code
          captured.output = result.output
          captured.file = ctx.file
          return 'bad input'
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_longrun_custom_summary.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'testprov', provider, ctx)

      vim.wait(3000, function()
        return notified_fail
      end, 50)

      vim.notify = orig
      assert.is_true(notified_fail)
      assert.is_nil(captured.code)
      assert.are.equal('/tmp/preview_test_longrun_custom_summary.txt', captured.file)
      assert.is_truthy(captured.output:find('bad input', 1, true))

      compiler.stop(bufnr)
      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)
      helpers.delete_buffer(bufnr)
    end)

    it('hints :Preview output when long-running compile exits without structured errors', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_longrun_output_hint.txt')
      vim.bo[bufnr].modified = false

      local notified_fail = false
      local orig = vim.notify
      vim.notify = function(msg, level)
        if msg == '[preview.nvim]: compilation failed (see :Preview output)' then
          notified_fail = level == vim.log.levels.ERROR
        end
      end

      local provider = {
        cmd = { 'sh' },
        reload = function()
          return { 'sh', '-c', 'echo "fatal compiler output" >&2; exit 12' }
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_longrun_output_hint.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'testprov', provider, ctx)

      vim.wait(3000, function()
        return notified_fail
      end, 50)

      vim.notify = orig
      assert.is_true(notified_fail)
      assert.is_truthy(compiler.result(bufnr).output:find('fatal compiler output', 1, true))
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('stop', function()
    it('does nothing when no process is active', function()
      assert.has_no.errors(function()
        compiler.stop(999)
      end)
    end)
  end)

  describe('status', function()
    it('returns idle for buffer with no process', function()
      local s = compiler.status(42)
      assert.is_false(s.compiling)
    end)

    it('returns compiling during active process', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_status.txt')
      vim.bo[bufnr].modified = false

      local provider = { cmd = { 'sleep', '10' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_status.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'sleepcmd', provider, ctx)
      local s = compiler.status(bufnr)
      assert.is_true(s.compiling)
      assert.are.equal('sleepcmd', s.provider)

      compiler.stop(bufnr)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('open', function()
    it('returns false when no output exists', function()
      assert.is_false(compiler.open(999))
    end)

    it('returns true after compilation stores output', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_open.txt')
      vim.bo[bufnr].modified = false

      local provider = {
        cmd = { 'true' },
        output = function()
          return '/tmp/preview_test_open.pdf'
        end,
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_open.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'testprov', provider, ctx)
      local s = compiler._test.state[bufnr]
      assert.is_not_nil(s)
      assert.are.equal('/tmp/preview_test_open.pdf', s.output)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('output', function()
    it('returns false when no compiler result exists', function()
      assert.is_false(compiler.output(999))
    end)

    it('opens an output buffer with stored compiler output', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_output.txt')
      vim.bo[bufnr].modified = false

      local provider = {
        cmd = {
          'sh',
          '-c',
          [[printf '%s\n' 'stdout line'
printf '%s\n' 'stderr line' >&2
exit 12]],
        },
      }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_output.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'testprov', provider, ctx)

      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)

      assert.is_true(compiler.output(bufnr))
      local output_bufnr = vim.api.nvim_get_current_buf()
      local lines = vim.api.nvim_buf_get_lines(output_bufnr, 0, -1, false)
      assert.is_truthy(table.concat(lines, '\n'):find('stdout line', 1, true))
      assert.is_truthy(table.concat(lines, '\n'):find('stderr line', 1, true))
      helpers.delete_buffer(output_bufnr)
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('toggle', function()
    it('starts watching and sets watching flag', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch.txt')

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return { bufnr = b, file = '/tmp/preview_test_watch.txt', root = '/tmp', ft = 'text' }
      end

      compiler.toggle(bufnr, 'echo', provider, ctx_builder)
      assert.is_true(compiler.status(bufnr).watching)

      helpers.delete_buffer(bufnr)
    end)

    it('toggles off when called again', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch_toggle.txt')

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return { bufnr = b, file = '/tmp/preview_test_watch_toggle.txt', root = '/tmp', ft = 'text' }
      end

      compiler.toggle(bufnr, 'echo', provider, ctx_builder)
      assert.is_true(compiler.status(bufnr).watching)

      compiler.toggle(bufnr, 'echo', provider, ctx_builder)
      assert.is_false(compiler.status(bufnr).watching)

      helpers.delete_buffer(bufnr)
    end)

    it('stop_all clears watches', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch_stopall.txt')

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return {
          bufnr = b,
          file = '/tmp/preview_test_watch_stopall.txt',
          root = '/tmp',
          ft = 'text',
        }
      end

      compiler.toggle(bufnr, 'echo', provider, ctx_builder)
      assert.is_true(compiler.status(bufnr).watching)

      compiler.stop_all()
      assert.is_false(compiler.status(bufnr).watching)

      helpers.delete_buffer(bufnr)
    end)

    it('status includes watching state', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch_status.txt')

      local s = compiler.status(bufnr)
      assert.is_false(s.watching)

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return { bufnr = b, file = '/tmp/preview_test_watch_status.txt', root = '/tmp', ft = 'text' }
      end

      compiler.toggle(bufnr, 'echo', provider, ctx_builder)
      s = compiler.status(bufnr)
      assert.is_true(s.watching)

      compiler.unwatch(bufnr)
      helpers.delete_buffer(bufnr)
    end)
  end)
end)
