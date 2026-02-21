# Home Manager configuration for gity user
{ outputs, ... }:
{
  imports = [
    ../../modules/common/nixpkgs.nix
  ]
  ++ (with outputs.modules.home-manager; [
    pkgs
  ]);

  home = {
    username = "gity";
    homeDirectory = "/home/gity";
    enableNixpkgsReleaseCheck = false;
  };

  programs.home-manager.enable = true;
  systemd.user.startServices = "sd-switch";
  home.stateVersion = "24.11";
}
