#!/bin/bash
# Tear down the direct-link DHCP server set up by mirror-dhcp-up.sh (macOS).
# Usage: mirror-dhcp-down.sh <interface>   (e.g. en0)
set -uo pipefail
IFACE="${1:-}"
[ -n "$IFACE" ] || { echo "Usage: $0 <interface> (e.g. en0)" >&2; exit 2; }

sudo launchctl unload -w /System/Library/LaunchDaemons/bootps.plist 2>/dev/null || true
if [ -f /tmp/bootpd.plist.bak ]; then
  sudo cp /tmp/bootpd.plist.bak /etc/bootpd.plist
else
  # No prior config to restore; remove the one we wrote. Use your trash tool if you
  # have one; plain rm is shown for a self-contained public script.
  sudo rm -f /etc/bootpd.plist
fi
sudo ifconfig "$IFACE" inet 10.77.0.1 -alias 2>/dev/null || true
echo "down: DHCP stopped, $IFACE alias removed"
