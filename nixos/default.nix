{
  inputs,
  outputs,
  ...
}:
{
  # more-jump-more は現在使用停止中（ファイルは保持）
  # "more-jump-more" = inputs.nixpkgs.lib.nixosSystem {
  #   specialArgs = { inherit inputs outputs; };
  #   modules = [
  #     inputs.home-manager.nixosModules.home-manager
  #     ./more-jump-more
  #   ];
  # };

  "monooki" = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs outputs; };
    modules = [
      inputs.home-manager.nixosModules.home-manager
      ./monooki
    ];
  };
}
