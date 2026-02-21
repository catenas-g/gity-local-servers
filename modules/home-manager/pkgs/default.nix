{ pkgs, ... }:
{
  home.packages = with pkgs; [
    git
    nano
    gh
  ];
}
