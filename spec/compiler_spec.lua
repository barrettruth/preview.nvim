local helpers = require('spec.helpers')

describe('compiler', function()
  local compiler

  before_each(function()
    helpers.reset_config()
    compiler = require('preview.compiler')
  end)

  describe('compile', function()
    it('spawns a process and tracks it in active table', function()
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
      local active = compiler._test.active
      assert.is_not_nil(active[bufnr])
      assert.are.equal('echo', active[bufnr].provider)

      vim.wait(2000, function()
        return active[bufnr] == nil
      end, 50)

      assert.is_nil(active[bufnr])
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

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/preview_test_event.txt',
        root = '/tmp',
        ft = 'text',
      }

      compiler.compile(bufnr, 'echo', provider, ctx)
      assert.is_true(fired)

      vim.wait(2000, function()
        return compiler._test.active[bufnr] == nil
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
        return compiler._test.active[bufnr] == nil
      end, 50)

      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('watch', function()
    it('registers autocmd and tracks in watching table', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch.txt')

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return { bufnr = b, file = '/tmp/preview_test_watch.txt', root = '/tmp', ft = 'text' }
      end

      compiler.watch(bufnr, 'echo', provider, ctx_builder)
      assert.is_not_nil(compiler._test.watching[bufnr])

      helpers.delete_buffer(bufnr)
    end)

    it('fires PreviewWatchStarted event', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch_event.txt')

      local fired = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'PreviewWatchStarted',
        once = true,
        callback = function()
          fired = true
        end,
      })

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return { bufnr = b, file = '/tmp/preview_test_watch_event.txt', root = '/tmp', ft = 'text' }
      end

      compiler.watch(bufnr, 'echo', provider, ctx_builder)
      assert.is_true(fired)

      compiler.unwatch(bufnr)
      helpers.delete_buffer(bufnr)
    end)

    it('toggles off when called again', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch_toggle.txt')

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return { bufnr = b, file = '/tmp/preview_test_watch_toggle.txt', root = '/tmp', ft = 'text' }
      end

      compiler.watch(bufnr, 'echo', provider, ctx_builder)
      assert.is_not_nil(compiler._test.watching[bufnr])

      compiler.watch(bufnr, 'echo', provider, ctx_builder)
      assert.is_nil(compiler._test.watching[bufnr])

      helpers.delete_buffer(bufnr)
    end)

    it('fires PreviewWatchStopped on unwatch', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/preview_test_watch_stop.txt')

      local stopped = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'PreviewWatchStopped',
        once = true,
        callback = function()
          stopped = true
        end,
      })

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx_builder = function(b)
        return { bufnr = b, file = '/tmp/preview_test_watch_stop.txt', root = '/tmp', ft = 'text' }
      end

      compiler.watch(bufnr, 'echo', provider, ctx_builder)
      compiler.unwatch(bufnr)
      assert.is_true(stopped)
      assert.is_nil(compiler._test.watching[bufnr])

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

      compiler.watch(bufnr, 'echo', provider, ctx_builder)
      assert.is_not_nil(compiler._test.watching[bufnr])

      compiler.stop_all()
      assert.is_nil(compiler._test.watching[bufnr])

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

      compiler.watch(bufnr, 'echo', provider, ctx_builder)
      s = compiler.status(bufnr)
      assert.is_true(s.watching)

      compiler.unwatch(bufnr)
      helpers.delete_buffer(bufnr)
    end)
  end)
end)
