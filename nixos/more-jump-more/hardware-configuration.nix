{ inputs, modulesPath, ... }:
{
  imports = [
    inputs.nixos-hardware.nixosModules.raspberry-pi-4
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  sdImage.compressImage = false;

  hardware.enableRedistributableFirmware = true;

  # Cross-compilation: build on x86_64, target aarch64
  nixpkgs.buildPlatform.system = "x86_64-linux";
  nixpkgs.hostPlatform.system = "aarch64-linux";

  # Allow missing kernel modules (e.g. dw-hdmi renamed in newer kernels)
  nixpkgs.overlays = [
    (_final: prev: {
      makeModulesClosure = args: prev.makeModulesClosure (args // { allowMissing = true; });
    })
  ];
}
