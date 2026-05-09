# Contributing

Development, issues, and pull requests happen on
[Forgejo](https://git.barrettruth.com/barrettruth/preview.nvim).

## Scope

preview.nvim is a Neovim plugin for previewing supported files from the editor.
It is not a browser, document conversion framework, or general file manager.

## Pull Requests

Bug fixes and documentation fixes are welcome. AI-generated contributions are
not accepted.

For new behavior, open an issue first unless the change is small and already
fits the project's scope.

Behavior or configuration changes should update `README.md` and
`doc/preview.txt` when appropriate.

## Development

It is preferred to use the Nix development shell, which bundles all necessary
tools:

```sh
nix develop
```

## Checks

Run the local checks before opening a pull request:

```sh
nix develop --command just ci
```
