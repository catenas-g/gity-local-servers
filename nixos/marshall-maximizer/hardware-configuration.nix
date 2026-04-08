# Hardware configuration for marshall-maximizer (Raspberry Pi 5)
{
  lib,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "nvme"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  boot.growPartition = true;

  fileSystems."/" = {
    device = lib.mkForce "/dev/disk/by-uuid/e5525414-3d27-45d3-99f5-ec56750ce6ac";
    fsType = "ext4";
    autoResize = true;
  };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
