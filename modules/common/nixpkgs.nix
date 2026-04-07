# Centralized nixpkgs configuration
{ outputs, ... }:
{
  nixpkgs = {
    overlays = [
      outputs.overlays.unstable-packages
      outputs.overlays.custom-packages
    ];

    config = {
      allowUnfree = true;
    };
  };
}
