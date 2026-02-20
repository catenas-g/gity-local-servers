# Home Manager configuration for panoption-chan (Ubuntu server)
{ outputs, ... }:
{
  imports = [
    ../../modules/common/nixpkgs.nix
  ];

  home = {
    username = "gity";
    homeDirectory = "/home/gity";
    enableNixpkgsReleaseCheck = false;
  };

  programs.home-manager.enable = true;
  systemd.user.startServices = "sd-switch";
  home.stateVersion = "24.11";
}
