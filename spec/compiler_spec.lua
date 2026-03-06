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
        if msg:find('compilation failed') and level == vim.log.levels.ERROR then
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

      compiler.stop(bufnr)
      vim.wait(2000, function()
        return process_done(bufnr)
      end, 50)
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
