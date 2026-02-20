# CLAUDE.md

AI assistant guidance for Gity Local Servers Nix repository.

## Quick Links

### Setup & Validation

- [Validation Guide](docs/setup/validation.md) - **ALWAYS validate after .nix changes**

### Reference

- [Architecture](headscale-caddy-l4-raspi-architecture.md) - Headscale + Caddy L4 architecture

### Guides

- [Nix Language](docs/guides/nix-language.md) - Language quick reference

### Troubleshooting

- [Common Issues](docs/troubleshooting/common-issues.md) - Debug commands & fixes

## Essential Rules

1. **ALWAYS format with nix fmt** before committing or after any file change:

   ```bash
   nix fmt
   ```

2. **ALWAYS validate** after any `.nix` file change:

   ```bash
   nix flake check --extra-experimental-features 'nix-command flakes'
   ```

3. **Repository**: Nix Flakes for NixOS and Home Manager
4. **Platforms**: NixOS (aarch64-linux, x86_64-linux)
5. **Main configs**: `more-jump-more` (NixOS/aarch64), `panoption-chan` (Home Manager)
6. **Modules**: headscale, caddy-l4, tailscale, cloudflare-ddns, ssh-server

## Auto-Update Policy

When discovering new Nix information through web searches or problem-solving, automatically update relevant documentation
files without being asked.
