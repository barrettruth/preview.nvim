local helpers = require('spec.helpers')

describe('diagnostic', function()
  local diagnostic

  before_each(function()
    helpers.reset_config()
    diagnostic = require('preview.diagnostic')
  end)

  describe('clear', function()
    it('clears diagnostics for a buffer', function()
      local bufnr = helpers.create_buffer({ 'line1', 'line2' })
      local ns = diagnostic.get_namespace()
      vim.diagnostic.set(ns, bufnr, {
        { lnum = 0, col = 0, message = 'test error', severity = vim.diagnostic.severity.ERROR },
      })

      local diags = vim.diagnostic.get(bufnr, { namespace = ns })
      assert.are.equal(1, #diags)

      diagnostic.clear(bufnr)

      diags = vim.diagnostic.get(bufnr, { namespace = ns })
      assert.are.equal(0, #diags)
      helpers.delete_buffer(bufnr)
    end)
  end)

  describe('set', function()
    it('sets diagnostics from error_parser output', function()
      local bufnr = helpers.create_buffer({ 'line1', 'line2' })
      local ns = diagnostic.get_namespace()

      local parser = function()
        return {
          { lnum = 0, col = 0, message = 'syntax error', severity = vim.diagnostic.severity.ERROR },
        }
      end

      local ctx = { bufnr = bufnr, file = '/tmp/test.typ', root = '/tmp', ft = 'typst' }
      diagnostic.set(bufnr, 'typst', parser, 'error on line 1', ctx)

      local diags = vim.diagnostic.get(bufnr, { namespace = ns })
      assert.are.equal(1, #diags)
      assert.are.equal('syntax error', diags[1].message)
      assert.are.equal('typst', diags[1].source)
      helpers.delete_buffer(bufnr)
    end)

    it('sets source to provider name when not specified', function()
      local bufnr = helpers.create_buffer({ 'line1' })
      local ns = diagnostic.get_namespace()

      local parser = function()
        return {
          { lnum = 0, col = 0, message = 'err', severity = vim.diagnostic.severity.ERROR },
        }
      end

      local ctx = { bufnr = bufnr, file = '/tmp/test.tex', root = '/tmp', ft = 'tex' }
      diagnostic.set(bufnr, 'latexmk', parser, 'error', ctx)

      local diags = vim.diagnostic.get(bufnr, { namespace = ns })
      assert.are.equal('latexmk', diags[1].source)
      helpers.delete_buffer(bufnr)
    end)

    it('preserves existing source from parser', function()
      local bufnr = helpers.create_buffer({ 'line1' })
      local ns = diagnostic.get_namespace()

      local parser = function()
        return {
          {
            lnum = 0,
            col = 0,
            message = 'err',
            severity = vim.diagnostic.severity.ERROR,
            source = 'custom',
          },
        }
      end

      local ctx = { bufnr = bufnr, file = '/tmp/test.tex', root = '/tmp', ft = 'tex' }
      diagnostic.set(bufnr, 'latexmk', parser, 'error', ctx)

      local diags = vim.diagnostic.get(bufnr, { namespace = ns })
      assert.are.equal('custom', diags[1].source)
      helpers.delete_buffer(bufnr)
    end)

    it('handles parser failure gracefully', function()
      local bufnr = helpers.create_buffer({ 'line1' })
      local ns = diagnostic.get_namespace()

      local parser = function()
        error('parser exploded')
      end

      local ctx = { bufnr = bufnr, file = '/tmp/test.tex', root = '/tmp', ft = 'tex' }

      assert.has_no.errors(function()
        diagnostic.set(bufnr, 'latexmk', parser, 'error', ctx)
      end)

      local diags = vim.diagnostic.get(bufnr, { namespace = ns })
      assert.are.equal(0, #diags)
      helpers.delete_buffer(bufnr)
    end)

    it('does nothing when parser returns empty list', function()
      local bufnr = helpers.create_buffer({ 'line1' })
      local ns = diagnostic.get_namespace()

      local parser = function()
        return {}
      end

      local ctx = { bufnr = bufnr, file = '/tmp/test.tex', root = '/tmp', ft = 'tex' }
      diagnostic.set(bufnr, 'latexmk', parser, 'error', ctx)

      local diags = vim.diagnostic.get(bufnr, { namespace = ns })
      assert.are.equal(0, #diags)
      helpers.delete_buffer(bufnr)
    end)
  end)
end)
