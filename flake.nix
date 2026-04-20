{
  description = "preview.nvim — async document compilation for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
    vimdoc-language-server.url = "github:barrettruth/vimdoc-language-server";
  };

  outputs =
    {
      nixpkgs,
      systems,
      vimdoc-language-server,
      ...
    }:
    let
      forEachSystem =
        f: nixpkgs.lib.genAttrs (import systems) (system: f nixpkgs.legacyPackages.${system});
    in
    {
      formatter = forEachSystem (pkgs: pkgs.nixfmt-tree);

      devShells = forEachSystem (
        pkgs:
        let
          devTools = [
            (pkgs.luajit.withPackages (
              ps: with ps; [
                busted
                nlua
              ]
            ))
            pkgs.just
            pkgs.prettier
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
            vimdoc-language-server.packages.${pkgs.system}.default
          ];
          devPackages = devTools ++ [
            pkgs.neovim
            pkgs.typst
            pkgs.texliveMedium
            pkgs.tectonic
            pkgs.pandoc
            pkgs.asciidoctor
            pkgs.quarto
            pkgs.plantuml
            pkgs.mermaid-cli
            pkgs.zathura
            pkgs.sioyek
          ];
          devShell = pkgs.mkShell {
            packages = devPackages;
          };
        in
        {
          default = pkgs.mkShell {
            packages = devTools;
          };
          dev = devShell;
          ci = pkgs.mkShell {
            packages = devTools ++ [
              pkgs.neovim
            ];
          };
          presets = devShell;
        }
      );
    };
}
