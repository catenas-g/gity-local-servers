{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "fireactions";
  version = "2.0.4";

  src = fetchFromGitHub {
    owner = "hostinger";
    repo = "fireactions";
    rev = "v${version}";
    hash = "sha256-K7aTznPdYSsYNq39l6GzvF0iRZ0xQSs1XujlTyns30s=";
  };

  vendorHash = "sha256-E0kq0jLOQG/w3mEmnsKH9EqiT3EiI0bqEE4f9U2W40M=";

  subPackages = [ "cmd/fireactions" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/hostinger/fireactions.Version=${version}"
    "-X github.com/hostinger/fireactions.Commit=v${version}"
  ];

  meta = with lib; {
    description = "Self-hosted GitHub Actions runners on Firecracker microVMs";
    homepage = "https://github.com/hostinger/fireactions";
    license = licenses.asl20;
    mainProgram = "fireactions";
  };
}
