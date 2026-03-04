#!/bin/sh
set -eu

nix develop --command stylua --check .
git ls-files '*.lua' | xargs nix develop --command selene --display-style quiet
nix develop --command prettier --check .
nix fmt
git diff --exit-code -- '*.nix'
nix develop --command lua-language-server --check lua/ --configpath "$(pwd)/.luarc.json" --checklevel=Warning
nix develop --command busted
