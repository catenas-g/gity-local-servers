{
  inputs,
  outputs,
  ...
}:
{
  "more-jump-more" = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs outputs; };
    modules = [
      ./more-jump-more
    ];
  };
}
