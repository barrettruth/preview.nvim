local helpers = require('spec.helpers')

describe('render', function()
  local render

  before_each(function()
    helpers.reset_config()
    render = require('render')
  end)

  describe('config', function()
    it('accepts nil config', function()
      vim.g.render = nil
      assert.has_no.errors(function()
        render.get_config()
      end)
    end)

    it('applies default values', function()
      vim.g.render = nil
      local config = render.get_config()
      assert.is_false(config.debug)
      assert.are.same({}, config.providers)
      assert.are.same({}, config.providers_by_ft)
    end)

    it('merges user config with defaults', function()
      vim.g.render = { debug = true }
      helpers.reset_config()
      local config = require('render').get_config()
      assert.is_true(config.debug)
      assert.are.same({}, config.providers)
    end)

    it('accepts full provider config', function()
      vim.g.render = {
        providers = {
          typst = {
            cmd = { 'typst', 'compile' },
            args = { '%s' },
          },
        },
        providers_by_ft = {
          typst = 'typst',
        },
      }
      helpers.reset_config()
      local config = require('render').get_config()
      assert.is_not_nil(config.providers.typst)
      assert.are.equal('typst', config.providers_by_ft.typst)
    end)
  end)

  describe('resolve_provider', function()
    before_each(function()
      vim.g.render = {
        providers = {
          typst = { cmd = { 'typst', 'compile' } },
        },
        providers_by_ft = {
          typst = 'typst',
        },
      }
      helpers.reset_config()
      render = require('render')
    end)

    it('returns provider name for mapped filetype', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local name = render.resolve_provider(bufnr)
      assert.are.equal('typst', name)
      helpers.delete_buffer(bufnr)
    end)

    it('returns nil for unmapped filetype', function()
      local bufnr = helpers.create_buffer({}, 'lua')
      local name = render.resolve_provider(bufnr)
      assert.is_nil(name)
      helpers.delete_buffer(bufnr)
    end)

    it('returns nil when provider name maps to missing config', function()
      vim.g.render = {
        providers = {},
        providers_by_ft = { typst = 'typst' },
      }
      helpers.reset_config()
      local bufnr = helpers.create_buffer({}, 'typst')
      local name = require('render').resolve_provider(bufnr)
      assert.is_nil(name)
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('build_context', function()
    it('builds context from buffer', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local ctx = render.build_context(bufnr)
      assert.are.equal(bufnr, ctx.bufnr)
      assert.are.equal('typst', ctx.ft)
      assert.is_string(ctx.file)
      assert.is_string(ctx.root)
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('status', function()
    it('returns idle when nothing is compiling', function()
      local bufnr = helpers.create_buffer({})
      local s = render.status(bufnr)
      assert.is_false(s.compiling)
      assert.is_nil(s.provider)
      helpers.delete_buffer(bufnr)
    end)
  end)
end)
