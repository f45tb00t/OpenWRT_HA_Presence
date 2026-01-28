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

## Debug
- Enable logging: set `DEBUG=1` in `/etc/presence/presence.conf` and restart service:
  ```
  /etc/init.d/presence_hostapd restart
  ```
- Watch logs:
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
