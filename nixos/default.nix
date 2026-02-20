{
  inputs,
  outputs,
  ...
}:
{
  "more-jump-more" = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs outputs; };
    modules = [
      ./more-jump-more
    ];
  };
}
