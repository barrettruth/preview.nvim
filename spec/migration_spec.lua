require('spec.helpers')

local migration = require('preview.migration')

describe('migration', function()
  local system, executable, notify_once, sync_system
  local callback, command, options, notices, sync_calls

  before_each(function()
    system, executable = vim.system, vim.fn.executable
    notify_once, sync_system = vim.notify_once, vim.fn.system
    callback, command, options = nil, nil, nil
    notices, sync_calls = {}, 0
    vim.fn.executable = function()
      return 1
    end
    vim.fn.system = function()
      sync_calls = sync_calls + 1
      error('unexpected synchronous process')
    end
    vim.system = function(cmd, opts, cb)
      command, options, callback = cmd, opts, cb
      return {
        wait = function()
          error('unexpected process wait')
        end,
      }
    end
    vim.notify_once = function(message, level)
      assert.is_false(vim.in_fast_event())
      table.insert(notices, { message = message, level = level })
    end
  end)

  after_each(function()
    vim.system, vim.fn.executable = system, executable
    vim.notify_once, vim.fn.system = notify_once, sync_system
    assert.are.equal(0, sync_calls)
  end)

  it('matches only the existing GitHub origins', function()
    for _, origin in ipairs({
      'https://github.com/barrettruth/preview.nvim',
      'http://github.com/barrettruth/preview.nvim',
      'git://github.com/barrettruth/preview.nvim',
      'ssh://git@github.com/barrettruth/preview.nvim',
      'git@github.com:barrettruth/preview.nvim',
    }) do
      for _, suffix in ipairs({ '', '.git', '/', '.git///' }) do
        assert.is_true(migration.is_github_origin(origin .. suffix))
      end
    end
    for _, origin in ipairs({
      'https://forge.barrettruth.com/barrettruth/preview.nvim',
      'https://github.com/other/preview.nvim',
      'https://github.com/barrettruth/other.nvim',
      'https://github.com/barrettruth/preview.nvim-extra',
      'https://github.com.evil/barrettruth/preview.nvim',
      '',
      false,
      {},
    }) do
      assert.is_false(migration.is_github_origin(origin))
    end
    assert.is_false(migration.is_github_origin(nil))
  end)

  it('returns before the subprocess callback and schedules the warning', function()
    migration.warn_if_github_source('/isolated/plugin')
    assert.are.same(
      { 'git', '-C', '/isolated/plugin', 'config', '--get', 'remote.origin.url' },
      command
    )
    assert.are.same({ text = true }, options)
    assert.are.equal('function', type(callback))
    assert.are.equal(0, #notices)

    local fast_event = false
    local timer = assert(vim.uv.new_timer())
    timer:start(0, 0, function()
      fast_event = vim.in_fast_event()
      callback({ code = 0, stdout = ' \nhttps://github.com/barrettruth/preview.nvim.git\n' })
      timer:close()
    end)
    assert.is_true(vim.wait(1000, function()
      return #notices == 1
    end))
    assert.is_true(fast_event)
    assert.are.equal(vim.log.levels.WARN, notices[1].level)
    assert.are.equal(
      '[preview.nvim] This repository will be removed from GitHub on October 31, 2026. '
        .. 'Install from Forgejo: https://forge.barrettruth.com/barrettruth/preview.nvim. '
        .. 'See :help preview-migration.',
      notices[1].message
    )
  end)

  it('uses the plugin root when no root is supplied', function()
    migration.warn_if_github_source()
    assert.are.equal(migration.plugin_root(), command[3])
  end)

  for _, result in ipairs({
    { code = 1, stdout = 'https://github.com/barrettruth/preview.nvim' },
    { code = 128, stderr = 'not a git repository' },
    { code = 0 },
    { code = 0, stdout = '' },
    { code = 0, stdout = 'https://forge.barrettruth.com/barrettruth/preview.nvim.git\n' },
  }) do
    it('stays quiet for result ' .. vim.inspect(result), function()
      migration.warn_if_github_source('/isolated/plugin')
      callback(result)
      local drained = false
      vim.schedule(function()
        drained = true
      end)
      assert.is_true(vim.wait(1000, function()
        return drained
      end))
      assert.are.equal(0, #notices)
    end)
  end

  it('stays quiet when Git is missing', function()
    vim.fn.executable = function()
      return 0
    end
    migration.warn_if_github_source('/isolated/plugin')
    assert.is_nil(command)
    assert.are.equal(0, #notices)
  end)

  it('stays quiet when process creation fails', function()
    vim.system = function()
      error('spawn failed')
    end
    assert.has_no.errors(function()
      migration.warn_if_github_source('/isolated/plugin')
    end)
    assert.are.equal(0, #notices)
  end)

  it('reads an origin with a real asynchronous Git process', function()
    vim.system, vim.fn.executable = system, executable
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, 'p')
    local ok, err = pcall(function()
      assert.are.equal(0, system({ 'git', 'init', root }):wait().code)
      assert.are.equal(
        0,
        system({
          'git',
          '-C',
          root,
          'config',
          'remote.origin.url',
          'git@github.com:barrettruth/preview.nvim.git',
        }):wait().code
      )
      migration.warn_if_github_source(root)
      assert.are.equal(0, #notices)
      assert.is_true(vim.wait(2000, function()
        return #notices == 1
      end))
    end)
    vim.fn.delete(root, 'rf')
    assert.is_true(ok, err)
  end)
end)
