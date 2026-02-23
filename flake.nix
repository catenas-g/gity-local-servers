{
  description = "Gity Local Servers";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self, ... }@inputs:
    let
      inherit (self) outputs;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems =
        f:
        builtins.listToAttrs (
          map (system: {
            name = system;
            value = f system;
          }) systems
        );
    in
    let
      treefmtEval =
        system: inputs.treefmt-nix.lib.evalModule (import inputs.nixpkgs { inherit system; }) ./treefmt.nix;
    in
    {
      # Formatter available through 'nix fmt'
      formatter = forAllSystems (system: (treefmtEval system).config.build.wrapper);

      # Overlays
      overlays = import ./overlays { inherit inputs; };

      # Modules
      modules = import ./modules;

      # SD card image (cross-compiled from x86_64-linux)
      packages.x86_64-linux.sdImage = self.nixosConfigurations.more-jump-more.config.system.build.sdImage;

      # NixOS
      nixosConfigurations = import ./nixos { inherit inputs outputs; };

      # Home Manager
      homeConfigurations = import ./home-manager { inherit inputs outputs; };
    };
}
