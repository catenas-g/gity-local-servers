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
}
