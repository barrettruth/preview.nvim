local migration = require('preview.migration')

describe('migration', function()
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
end)
