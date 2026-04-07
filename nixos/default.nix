{
  inputs,
  outputs,
  ...
}:
{
  "more-jump-more" = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs outputs; };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ./more-jump-more
    ];
  };

  "monooki" = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs outputs; };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ./monooki
    ];
  };

  "errand-ensemble-1" = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs outputs; };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ./errand-ensemble-1
    ];
  };

  "errand-ensemble-2" = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs outputs; };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ./errand-ensemble-2
    ];
  };

  "marshall-maximizer" = inputs.nixos-raspberrypi.lib.nixosSystem {
    specialArgs = { inherit inputs outputs; };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ./marshall-maximizer
    ];
  };
}
