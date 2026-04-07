# Common base configuration shared across all NixOS machines
{
  inputs,
  outputs,
  pkgs,
  ...
}:
{
  imports = with outputs.modules.nixos; [
    attic-watch
  ];
  # --- Firewall logging ---
  networking.firewall = {
    logRefusedConnections = false;
    logRefusedPackets = false;
  };

  services.journald.extraConfig = ''
    ForwardToConsole=no
  '';

  boot.kernel.sysctl."kernel.printk" = "3 4 1 3";

  # --- NetworkManager ---
  networking.networkmanager.enable = true;

  # --- User ---
  users.users.gity = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "password";
    shell = pkgs.fish;
  };

  programs.fish.enable = true;

  # --- Home Manager ---
  home-manager = {
    extraSpecialArgs = { inherit inputs outputs; };
    users.gity = import ../../home-manager/gity;
  };

  security.sudo.wheelNeedsPassword = false;

  # --- Nix ---
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [
      "root"
      "@wheel"
    ];
    substituters = [
      "https://cache.nixos.org"
      "http://192.168.128.199:8080/gity"
      "https://nixos-raspberrypi.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "gity:XeiT0KGhWFIQM9GxOGSa60X8axF0cSJBd92/DaIbXXY="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  # --- Locale ---
  time.timeZone = "Asia/Tokyo";

  system.stateVersion = "25.11";
}
