{
  description = "preview.nvim — async document compilation for Neovim";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs =
    {
      nixpkgs,
      systems,
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
            pkgs.neovim
            pkgs.just
            pkgs.biome
            pkgs.stylua
            pkgs.selene
            pkgs.lua-language-server
          ];
          devPackages = devTools ++ [
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
            VIMRUNTIME = "${pkgs.neovim}/share/nvim/runtime";
          };
        in
        {
          default = pkgs.mkShell {
            packages = devTools;
            VIMRUNTIME = "${pkgs.neovim}/share/nvim/runtime";
          };
          dev = devShell;
          presets = devShell;
        }
      );
    };
}
