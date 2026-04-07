{ inputs, ... }:
{
  # Access unstable packages via pkgs.unstable
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config = {
        allowUnfree = true;
      };
    };
  };

  # Custom packages
  custom-packages = final: _prev: {
    fireactions = final.callPackage ../packages/fireactions { };
    tc-redirect-tap = final.callPackage ../packages/tc-redirect-tap { };
  };
}
