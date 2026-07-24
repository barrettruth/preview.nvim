local M = {}

local mappings = {
  { 'toggle', 'Toggle document preview' },
  { 'compile', 'Compile document preview once' },
  { 'open', 'Open document preview output' },
  { 'output', 'Show document preview compiler output' },
  { 'clean', 'Clean document preview artifacts' },
}

local function callback(action)
  return function()
    require('preview')[action]()
  end
end

function M.setup()
  for _, mapping in ipairs(mappings) do
    local action, desc = unpack(mapping)
    vim.keymap.set('n', '<Plug>(preview-' .. action .. ')', callback(action), {
      silent = true,
      desc = desc,
    })
  end
end

return M
