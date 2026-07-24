local helpers = require('spec.helpers')

local definitions = {
  { 'toggle', 'Toggle document preview' },
  { 'compile', 'Compile document preview once' },
  { 'open', 'Open document preview output' },
  { 'output', 'Show document preview compiler output' },
  { 'clean', 'Clean document preview artifacts' },
}

local preview = require('preview')
local originals = {}

local function lhs(action)
  return '<Plug>(preview-' .. action .. ')'
end

describe('mappings', function()
  before_each(function()
    helpers.reset_config()
    for _, definition in ipairs(definitions) do
      local action = definition[1]
      originals[action] = preview[action]
      pcall(vim.keymap.del, 'n', lhs(action))
    end
  end)

  after_each(function()
    for _, definition in ipairs(definitions) do
      local action = definition[1]
      preview[action] = originals[action]
      pcall(vim.keymap.del, 'n', lhs(action))
    end
  end)

  it('defines the public normal-mode mappings', function()
    require('preview.mappings').setup()

    for _, definition in ipairs(definitions) do
      local action, desc = unpack(definition)
      local mapping = vim.fn.maparg(lhs(action), 'n', false, true)
      assert.are.equal(lhs(action), mapping.lhs)
      assert.are.equal(desc, mapping.desc)
      assert.are.equal(1, mapping.silent)
      assert.is_function(mapping.callback)
    end
  end)

  it('dispatches mappings through the public Lua API', function()
    local called = {}
    for _, definition in ipairs(definitions) do
      local action = definition[1]
      preview[action] = function()
        called[action] = (called[action] or 0) + 1
      end
    end

    require('preview.mappings').setup()

    for _, definition in ipairs(definitions) do
      local action = definition[1]
      vim.fn.maparg(lhs(action), 'n', false, true).callback()
      assert.are.equal(1, called[action])
    end
  end)
end)
