local helpers = require('spec.helpers')

describe('compiler', function()
  local compiler

  before_each(function()
    helpers.reset_config()
    compiler = require('render.compiler')
  end)

  describe('compile', function()
    it('spawns a process and tracks it in active table', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/render_test.txt')
      vim.bo[bufnr].modified = false

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/render_test.txt',
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

    it('fires RenderCompileStarted event', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/render_test_event.txt')
      vim.bo[bufnr].modified = false

      local fired = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'RenderCompileStarted',
        once = true,
        callback = function()
          fired = true
        end,
      })

      local provider = { cmd = { 'echo', 'ok' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/render_test_event.txt',
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

    it('fires RenderCompileSuccess on exit code 0', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/render_test_success.txt')
      vim.bo[bufnr].modified = false

      local succeeded = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'RenderCompileSuccess',
        once = true,
        callback = function()
          succeeded = true
        end,
      })

      local provider = { cmd = { 'true' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/render_test_success.txt',
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

    it('fires RenderCompileFailed on non-zero exit', function()
      local bufnr = helpers.create_buffer({ 'hello' }, 'text')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/render_test_fail.txt')
      vim.bo[bufnr].modified = false

      local failed = false
      vim.api.nvim_create_autocmd('User', {
        pattern = 'RenderCompileFailed',
        once = true,
        callback = function()
          failed = true
        end,
      })

      local provider = { cmd = { 'false' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/render_test_fail.txt',
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
      vim.api.nvim_buf_set_name(bufnr, '/tmp/render_test_status.txt')
      vim.bo[bufnr].modified = false

      local provider = { cmd = { 'sleep', '10' } }
      local ctx = {
        bufnr = bufnr,
        file = '/tmp/render_test_status.txt',
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
end)
