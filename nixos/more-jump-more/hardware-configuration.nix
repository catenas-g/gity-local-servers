{ inputs, modulesPath, ... }:
{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  sdImage.compressImage = false;

  hardware.enableRedistributableFirmware = true;

  nixpkgs.hostPlatform = "aarch64-linux";
}
