# NixOS configuration for errand-ensemble-1 (Raspberry Pi 4 GitHub Actions runner)
{
  inputs,
  outputs,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/common/nixpkgs.nix
    ../../modules/common/base.nix
    "${modulesPath}/installer/sd-card/sd-image-aarch64.nix"
  ]
  ++ (with outputs.modules.nixos; [
    ssh-server
    github-runner
  ]);

  # --- Networking ---
  networking = {
    hostName = "errand-ensemble-1";
    networkmanager.ensureProfiles.profiles.static-end0 = {
      connection = {
        id = "static-end0";
        type = "ethernet";
        interface-name = "end0";
        autoconnect = "true";
      };
      ipv4 = {
        method = "manual";
        addresses = "192.168.128.198/24";
        gateway = "192.168.128.1";
        dns = "192.168.128.1";
      };
    };
  };

  # --- User (SSH keys) ---
  users.users.gity.openssh.authorizedKeys.keys = [
    # hayao0819 - https://github.com/hayao0819.keys
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEz3ezIgiwbphtKP4zvHtAwyqUL+V+cz2k9DE9lsMA2/"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBsUNCEGNnXLxDlutnbifeorEfa9ESJKvyupLc+nigaX"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOEpke7Hffr3izxbvSR8h0YBVspo9GW/z0o/Nh2gkgmj"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ6XE1iBNLdoR2/fQHkTzU/UCwmkRc16mBDyzrJd8LrS"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDJltK3IAPFaIdr0t7+GDbOQU5HJYYxoe187tD02TofA"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMNdlRMbYOKk+IK0fwRJAG1UPbSipgBMX5w6+J8LzA7x"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFUSSN6zWJV9JXkGDC1tHJWkR7KfmqK5WLDJe2vz/LTI"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDhlsi4uUAHlln9fQGosDpHES2ioI/AAwPBkq0cU3k1B"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBy30rfndPXU2tZ6k1CzdJkt9un3Loa7TWdmi3oZQVZ0"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICVTZmV36YsXTlGVKKegRaG/TOz9MACtcvZPDB2AdJUt"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcWDTCBypBH1Z8XGIcBW7F8Po7nQqMThMM87FGnVo7V"
  ];
}
