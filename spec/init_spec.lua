local helpers = require('spec.helpers')

describe('preview', function()
  local preview

  before_each(function()
    helpers.reset_config()
    preview = require('preview')
  end)

  describe('config', function()
    it('accepts nil config', function()
      assert.has_no.errors(function()
        preview.get_config()
      end)
    end)

    it('applies default values', function()
      local config = preview.get_config()
      assert.is_false(config.debug)
      assert.are.same({}, config.providers)
    end)

    it('merges user config with defaults', function()
      helpers.reset_config({ debug = true })
      local config = require('preview').get_config()
      assert.is_true(config.debug)
      assert.are.same({}, config.providers)
    end)

    it('accepts full provider config', function()
      helpers.reset_config({
        providers = {
          typst = {
            cmd = { 'typst', 'compile' },
            args = { '%s' },
          },
        },
      })
      local config = require('preview').get_config()
      assert.is_not_nil(config.providers.typst)
    end)
  end)

  describe('resolve_provider', function()
    before_each(function()
      helpers.reset_config({
        providers = {
          typst = { cmd = { 'typst', 'compile' } },
        },
      })
      preview = require('preview')
    end)

    it('returns filetype when provider exists', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local name = preview.resolve_provider(bufnr)
      assert.are.equal('typst', name)
      helpers.delete_buffer(bufnr)
    end)

    it('returns nil for unconfigured filetype', function()
      local bufnr = helpers.create_buffer({}, 'lua')
      local name = preview.resolve_provider(bufnr)
      assert.is_nil(name)
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('build_context', function()
    it('builds context from buffer', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local ctx = preview.build_context(bufnr)
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
      local s = preview.status(bufnr)
      assert.is_false(s.compiling)
      assert.is_nil(s.provider)
      helpers.delete_buffer(bufnr)
    end)
  end)
end)
