#!/bin/bash
# Serve DHCP to the Mirror on one direct-link interface (macOS). No NAT, no
# internet forwarding. The Mirror MUST NOT reach the internet during OOBE, or it
# may update itself to a firmware where this ADB method no longer works.
#
# Usage: mirror-dhcp-up.sh <interface>   (e.g. en0)
set -euo pipefail
IFACE="${1:-}"
[ -n "$IFACE" ] || { echo "Usage: $0 <interface> (e.g. en0)" >&2; exit 2; }

HOST_IP="10.77.0.1"
NET="10.77.0.0"
MASK="255.255.255.0"
RANGE_LO="10.77.0.50"
RANGE_HI="10.77.0.60"

# Refuse to run if the host would forward the Mirror to the internet.
for key in net.inet.ip.forwarding net.inet6.ip6.forwarding; do
  val="$(sysctl -n "$key" 2>/dev/null || echo 0)"
  if [ "$val" != "0" ]; then
    echo "REFUSING: $key=$val. The Mirror must not reach the internet." >&2
    echo "Turn it off (sudo sysctl -w $key=0) and disable Internet Sharing first." >&2
    exit 1
  fi
done

sudo cp /etc/bootpd.plist /tmp/bootpd.plist.bak 2>/dev/null || true
sudo ifconfig "$IFACE" inet "$HOST_IP" netmask "$MASK" alias
sudo tee /etc/bootpd.plist >/dev/null <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
 <key>bootp_enabled</key><false/>
 <key>dhcp_enabled</key><array><string>$IFACE</string></array>
 <key>Subnets</key><array><dict>
  <key>name</key><string>mirror</string>
  <key>net_address</key><string>$NET</string>
  <key>net_mask</key><string>$MASK</string>
  <key>net_range</key><array><string>$RANGE_LO</string><string>$RANGE_HI</string></array>
  <key>allocate</key><true/>
  <key>dhcp_router</key><string>$HOST_IP</string>
 </dict></array>
</dict></plist>
P
sudo launchctl load -w /System/Library/LaunchDaemons/bootps.plist 2>/dev/null \
  || sudo launchctl kickstart -k system/com.apple.bootpd
echo "up: serving DHCP $RANGE_LO-$RANGE_HI on $IFACE, no NAT. Mirror lease: /var/db/dhcpd_leases"
