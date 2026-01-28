#!/bin/sh
set -eu

# Install runtime dependencies and enable the service.
# This is intended to be run on the OpenWrt AP.

opkg update
opkg install hostapd-utils mosquitto-client-ssl iw

chmod 600 /etc/presence/presence_mqtt.conf /etc/presence/presence_devices.conf /etc/presence/presence.conf || true
chmod 700 /etc/presence/presence_event.sh

/etc/init.d/presence_hostapd enable
/etc/init.d/presence_hostapd restart

echo "OK: presence_hostapd enabled and restarted"
