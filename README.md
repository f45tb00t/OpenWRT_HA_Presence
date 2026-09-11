# Presence bundle for OpenWrt (hostapd events -> MQTT -> Home Assistant)

## What it does
- Listens to hostapd connect/disconnect events on selected AP interfaces
- Publishes retained MQTT state per device (home / not_home)
- Adds a configurable grace timer before not_home to avoid brief Wi-Fi drops
- Stores temporary state in /tmp (RAM), no flash wear

## Files
- /etc/presence/presence_event.sh        Action script called by hostapd_cli -a
- /etc/presence/presence.conf            Settings (DEBUG, GRACE_SECONDS, IFACES)
- /etc/presence/presence_mqtt.conf       MQTT credentials
- /etc/presence/presence_devices.conf    MAC -> topic mapping
- /etc/presence/install.sh               Installs dependencies + enables service
- /etc/presence/healthcheck.sh           Checks deps + hostapd control sockets
- /etc/init.d/presence_hostapd           procd service

## Install (on the AP)
1) Copy bundle to the AP and extract at /
   ```
   scp -O OpenWRT_HA_Presence-main.zip root@192.168.0.1:/
   ```
2) Edit:
   - /etc/presence/presence.conf
   - /etc/presence/presence_mqtt.conf
   - /etc/presence/presence_devices.conf
3) Run:
   ```
   sh /etc/presence/install.sh
   ```

## Persist across OpenWrt sysupgrade

Add the Presence files to `/etc/sysupgrade.conf` so they are preserved during an OpenWrt upgrade:

```
/etc/presence/
/etc/init.d/presence_hostapd
```

You can add them with:

```
cat >> /etc/sysupgrade.conf <<'EOF'
/etc/presence/
/etc/init.d/presence_hostapd
EOF
```

Verify that the entries are present:

```
cat /etc/sysupgrade.conf
```

Verify that the Presence files are included in the sysupgrade backup:

```
sysupgrade -l | grep -E 'presence|presence_hostapd'
```

The required packages must also be present in the new firmware image:

```
hostapd-utils
mosquitto-client-ssl
iw
```

When using Attended Sysupgrade, make sure these packages are included in the new image and keep the configuration during the upgrade.

After the upgrade, verify the installation:

```
sh /etc/presence/healthcheck.sh
```

Check the service:

```
/etc/init.d/presence_hostapd status
```

If necessary, enable and restart it:

```
/etc/init.d/presence_hostapd enable
/etc/init.d/presence_hostapd restart
```

## Debug

Enable logging: set `DEBUG=1` in `/etc/presence/presence.conf` and restart service:

```
/etc/init.d/presence_hostapd restart
```

Watch logs:

```
logread -f | grep presence_event
```

## Home Assistant
Use MQTT `device_tracker` entities subscribed to the topics you configured in `presence_devices.conf`.

## Example configuration.yaml

```yaml
mqtt:
  device_tracker:
    - name: "Person One WIFI01 MQTT"
      state_topic: "presence/person_one_wifi01_mqtt"
      payload_home: "home"
      payload_not_home: "not_home"
      source_type: router

    - name: "Person Two WIFI01 MQTT"
      state_topic: "presence/person_two_wifi01_mqtt"
      payload_home: "home"
      payload_not_home: "not_home"
      source_type: router
```
