local migration = require('preview.migration')

describe('migration', function()
  local tmp
  local old_state_home
  local old_notify
  local notifications

  local function system(args)
    local output = vim.fn.system(args)
    assert.are.equal(0, vim.v.shell_error, output)
    return output
  end

  local function git_repo_with_origin(origin)
    local root = tmp .. '/repo'
    vim.fn.mkdir(root, 'p')
    system({ 'git', 'init', '--quiet', root })
    system({ 'git', '-C', root, 'remote', 'add', 'origin', origin })
    return root
  end

  local function marker_path()
    return vim.fn.stdpath('state') .. '/preview.nvim/' .. migration._test.marker_name
  end

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, 'p')
    old_state_home = vim.env.XDG_STATE_HOME
    vim.env.XDG_STATE_HOME = tmp .. '/state'
    vim.g[migration._test.session_key] = nil
    notifications = {}
    old_notify = vim.notify
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end
  end)

  after_each(function()
    vim.notify = old_notify
    vim.g[migration._test.session_key] = nil
    vim.env.XDG_STATE_HOME = old_state_home
    vim.fn.delete(tmp, 'rf')
  end)

  it('detects GitHub preview.nvim remotes', function()
    assert.is_true(
      migration._test.is_github_preview_source('https://github.com/barrettruth/preview.nvim')
    )
    assert.is_true(
      migration._test.is_github_preview_source('git@github.com:barrettruth/preview.nvim.git')
    )
    assert.is_true(
      migration._test.is_github_preview_source('ssh://git@github.com/barrettruth/preview.nvim.git')
    )
  end)

  it('does not match Forgejo or unrelated remotes', function()
    assert.is_false(
      migration._test.is_github_preview_source(
        'ssh://git@git.barrettruth.com/barrettruth/preview.nvim.git'
      )
    )
    assert.is_false(
      migration._test.is_github_preview_source('https://github.com/other/preview.nvim')
    )
    assert.is_false(
      migration._test.is_github_preview_source('https://github.com/barrettruth/other.nvim')
    )
  end)

  it('warns once and records a state marker for GitHub installs', function()
    local root = git_repo_with_origin('https://github.com/barrettruth/preview.nvim.git')

    migration.warn_if_github_source(root)
    migration.warn_if_github_source(root)

    assert.are.equal(1, #notifications)
    assert.are.equal(vim.log.levels.WARN, notifications[1].level)
    assert.are.equal(
      "[preview]: Due to GitHub's historic unreliability, development has moved to Forgejo. "
        .. 'See :help preview-migration to optionally update your plugin source configuration. '
        .. 'This is a one-time warning.',
      notifications[1].message
    )

    local marker = marker_path()
    assert.truthy(vim.uv.fs_stat(marker))
    assert.matches('^%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%dZ$', vim.fn.readfile(marker)[1])
  end)

  it('does not warn when the GitHub source marker already exists', function()
    local root = git_repo_with_origin('https://github.com/barrettruth/preview.nvim.git')
    local marker = marker_path()
    vim.fn.mkdir(vim.fn.fnamemodify(marker, ':h'), 'p')
    vim.fn.writefile({ '2026-05-04T00:00:00Z' }, marker)

    migration.warn_if_github_source(root)

    assert.are.equal(0, #notifications)
  end)

  it('does not warn for Forgejo installs', function()
    local root = git_repo_with_origin('ssh://git@git.barrettruth.com/barrettruth/preview.nvim.git')

    migration.warn_if_github_source(root)

    assert.are.equal(0, #notifications)
    assert.is_nil(vim.uv.fs_stat(marker_path()))
  end)
end)
