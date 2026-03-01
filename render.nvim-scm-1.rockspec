rockspec_format = '3.0'
package = 'render.nvim'
version = 'scm-1'

source = {
  url = 'git+https://github.com/barrettruth/render.nvim.git',
}

description = {
  summary = 'Async document compilation for Neovim',
  homepage = 'https://github.com/barrettruth/render.nvim',
  license = 'MIT',
}

dependencies = {
  'lua >= 5.1',
}

test_dependencies = {
  'nlua',
  'busted >= 2.1.1',
}

test = {
  type = 'busted',
}

build = {
  type = 'builtin',
}
