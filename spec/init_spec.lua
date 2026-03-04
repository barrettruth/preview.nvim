local helpers = require('spec.helpers')

describe('preview', function()
  local preview

  before_each(function()
    helpers.reset_config()
    preview = require('preview')
  end)

  describe('config', function()
    it('returns defaults before setup is called', function()
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

    it('merges override table with matching preset', function()
      helpers.reset_config({
        typst = {
          cmd = { 'typst', 'compile' },
          args = { '%s' },
        },
      })
      local config = require('preview').get_config()
      assert.is_not_nil(config.providers.typst)
    end)

    it('resolves preset = true to provider config', function()
      helpers.reset_config({ typst = true, markdown = true })
      local config = require('preview').get_config()
      local presets = require('preview.presets')
      assert.are.same(presets.typst, config.providers.typst)
      assert.are.same(presets.markdown, config.providers.markdown)
    end)

    it('resolves latex preset under tex filetype', function()
      helpers.reset_config({ latex = true })
      local config = require('preview').get_config()
      local presets = require('preview.presets')
      assert.are.same(presets.latex, config.providers.tex)
    end)

    it('resolves github preset under markdown filetype', function()
      helpers.reset_config({ github = true })
      local config = require('preview').get_config()
      local presets = require('preview.presets')
      assert.are.same(presets.github, config.providers.markdown)
    end)
  end)

  describe('resolve_provider', function()
    before_each(function()
      helpers.reset_config({
        typst = true,
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

  describe('statusline', function()
    it('returns empty string when idle', function()
      local bufnr = helpers.create_buffer({})
      assert.are.equal('', preview.statusline(bufnr))
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('unnamed buffer guard', function()
    before_each(function()
      helpers.reset_config({ typst = true })
      preview = require('preview')
    end)

    local function capture_notify(fn)
      local msg = nil
      local orig = vim.notify
      vim.notify = function(m)
        msg = m
      end
      fn()
      vim.notify = orig
      return msg
    end

    it('compile warns on unnamed buffer', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local msg = capture_notify(function()
        preview.compile(bufnr)
      end)
      assert.is_not_nil(msg)
      assert.is_truthy(msg:find('no file name'))
      helpers.delete_buffer(bufnr)
    end)

    it('toggle warns on unnamed buffer', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local msg = capture_notify(function()
        preview.toggle(bufnr)
      end)
      assert.is_not_nil(msg)
      assert.is_truthy(msg:find('no file name'))
      helpers.delete_buffer(bufnr)
    end)

    it('clean warns on unnamed buffer', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local msg = capture_notify(function()
        preview.clean(bufnr)
      end)
      assert.is_not_nil(msg)
      assert.is_truthy(msg:find('no file name'))
      helpers.delete_buffer(bufnr)
    end)

    it('open warns on unnamed buffer', function()
      local bufnr = helpers.create_buffer({}, 'typst')
      local msg = capture_notify(function()
        preview.open(bufnr)
      end)
      assert.is_not_nil(msg)
      assert.is_truthy(msg:find('no file name'))
      helpers.delete_buffer(bufnr)
    end)
  end)
end)
