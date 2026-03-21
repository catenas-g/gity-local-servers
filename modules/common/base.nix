# Common base configuration shared across all NixOS machines
{
  inputs,
  outputs,
  pkgs,
  ...
}:
{
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
  };

  # --- Locale ---
  time.timeZone = "Asia/Tokyo";

  system.stateVersion = "25.11";
}
