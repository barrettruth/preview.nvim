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
            pkgs.prettier
            pkgs.stylua
            pkgs.neovim
            pkgs.selene
            pkgs.lua-language-server
            vimdoc-language-server.packages.${pkgs.system}.default
          ];
        in
        {
          default = pkgs.mkShell {
            packages = devTools;
          };
          presets = pkgs.mkShell {
            packages = devTools ++ [
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
          };
        }
      );
    };
}
