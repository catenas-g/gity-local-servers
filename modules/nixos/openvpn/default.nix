{ pkgs, ... }:
{
  services.openvpn.servers.server = {
    config = ''
      port 1194
      proto udp
      dev tun

      ca /etc/openvpn/ca.pem
      cert /etc/openvpn/server.pem
      key /etc/openvpn/server-key.pem
      dh /etc/openvpn/dh2048.pem

      server 10.8.0.0 255.255.255.0

      push "route 192.168.128.0 255.255.255.0"

      keepalive 10 120
      cipher AES-256-GCM
      persist-key
      persist-tun
      verb 3
    '';
  };

  environment.systemPackages = [ pkgs.easyrsa ];

  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.nat = {
    enable = true;
    externalInterface = "end0";
    internalInterfaces = [ "tun0" ];
  };

  networking.firewall = {
    allowedUDPPorts = [ 1194 ];
    trustedInterfaces = [ "tun0" ];
  };
}
