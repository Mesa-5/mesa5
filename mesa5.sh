#!/bin/bash
# 01-pasarela.sh
# Ejecutar como root: sudo bash 01-pasarela.sh

set -e

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta este script como root"
    exit 1
fi

WAN="wlp0s20f3"
LAN="enp0s31f6"
LAN_IP="192.168.15.1"
RED="192.168.15.0/24"
NETPLAN="/etc/netplan/99-pasarela.yaml"
KEA="/etc/kea/kea-dhcp4.conf"

ip link show "$WAN" >/dev/null || { echo "No se encontró $WAN"; exit 1; }
ip link show "$LAN" >/dev/null || { echo "No se encontró $LAN"; exit 1; }

read -p "Nombre de la red WiFi (SSID): " WIFI_SSID
read -p "Contraseña del WiFi: " WIFI_PASS

apt update
apt install -y kea-dhcp4-server

mkdir -p /etc/netplan
[ -f "$NETPLAN" ] && cp "$NETPLAN" "${NETPLAN}.bak"

cat > "$NETPLAN" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN:
      dhcp4: false
      addresses:
        - $LAN_IP/24
  wifis:
    $WAN:
      dhcp4: true
      access-points:
        "$WIFI_SSID":
          password: "$WIFI_PASS"
EOF

chmod 600 "$NETPLAN"
netplan apply

[ -f "$KEA" ] && cp "$KEA" "${KEA}.bak"

cat > "$KEA" <<EOF
{
  "Dhcp4": {
    "interfaces-config": { "interfaces": [ "$LAN" ] },
    "lease-database": { "type": "memfile", "persist": true, "name": "/var/lib/kea/kea-leases4.csv" },
    "valid-lifetime": 3600,
    "subnet4": [{
      "id": 1,
      "subnet": "$RED",
      "pools": [{ "pool": "192.168.15.100 - 192.168.15.200" }],
      "option-data": [
        { "name": "routers", "data": "$LAN_IP" },
        { "name": "domain-name-servers", "data": "8.8.8.8, 1.1.1.1" },
        { "name": "domain-name", "data": "red.clase" }
      ]
    }]
  }
}
EOF

echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-pasarela.conf
sysctl -p /etc/sysctl.d/99-pasarela.conf

kea-dhcp4 -t "$KEA"

if systemctl list-unit-files | grep -q 'isc-kea-dhcp4-server'; then
    SERVICIO="isc-kea-dhcp4-server"
else
    SERVICIO="kea-dhcp4-server"
fi

systemctl enable "$SERVICIO"
systemctl restart "$SERVICIO"

echo "Se creó la pasarela correctamente."
