default:
    @just --list

format:
    nix fmt -- --ci
    stylua --check .
    biome ci .
    vimdoc-language-server format --check doc/

lint:
    git ls-files '*.lua' | xargs selene --display-style quiet
    lua-language-server --check lua/ --configpath "$(pwd)/.luarc.json" --checklevel=Warning
    vimdoc-language-server check doc/

test:
    busted

ci: format lint test
    @:
