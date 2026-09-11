# OpenWrt Wi-Fi Presence for Home Assistant

Event-driven Wi-Fi presence detection for Home Assistant using OpenWrt, `hostapd` events and MQTT.

The script runs directly on the OpenWrt access point and listens for Wi-Fi client connect/disconnect events from `hostapd`.

No polling of the router from Home Assistant is required.

---

## What it does

- Listens to `hostapd` connect/disconnect events on selected AP interfaces
- Publishes retained MQTT state per device:
  - `home`
  - `not_home`
- Publishes `home` immediately when a tracked device connects
- Uses a configurable grace period before publishing `not_home`
- Checks all configured local AP interfaces before declaring a device absent
- Handles normal roaming between 2.4 GHz and 5 GHz radios
- Stores temporary state in `/tmp` (RAM)
- Does not continuously poll the router
- Does not require SSH access from Home Assistant to OpenWrt

---

## How it works

```text
Wi-Fi client
     |
     v
OpenWrt / hostapd
     |
     | AP-STA-CONNECTED
     | AP-STA-DISCONNECTED
     v
presence_event.sh
     |
     v
MQTT
     |
     v
Home Assistant device_tracker
```

For every configured device:

### Connect

When `hostapd` reports:

```text
AP-STA-CONNECTED
```

the script immediately publishes:

```text
home
```

Any pending disconnect grace timer for that device is cancelled.

### Disconnect

When `hostapd` reports:

```text
AP-STA-DISCONNECTED
```

the script starts the configured grace timer.

After the grace period it checks whether the device is visible on any configured local Wi-Fi interface.

If the device is visible again, `not_home` is suppressed.

If the device is still absent, the script publishes:

```text
not_home
```

This avoids false `not_home` states during normal Wi-Fi roaming or short reconnects.

---

## Why hostapd events?

Many router integrations determine presence by periodically polling the router.

This project uses a different approach.

`hostapd` already knows when a Wi-Fi client connects or disconnects, so the script listens directly to those events.

This provides:

- immediate connect detection
- no periodic router polling
- no SSH connection from Home Assistant
- low CPU and network overhead
- simple MQTT integration

---

## Files

```text
/etc/presence/presence_event.sh
    Action script called by hostapd_cli -a

/etc/presence/presence.conf
    General settings:
    DEBUG
    GRACE_SECONDS
    IFACES
    TOPIC_PREFIX

/etc/presence/presence_mqtt.conf
    MQTT broker configuration and credentials

/etc/presence/presence_devices.conf
    MAC address -> MQTT topic mapping

/etc/presence/install.sh
    Installs dependencies and enables the service

/etc/presence/healthcheck.sh
    Checks required commands and hostapd control sockets

/etc/init.d/presence_hostapd
    OpenWrt procd service
```

---

# Configuration

## Wi-Fi interfaces

The script does not monitor SSIDs by name.

It listens only to the OpenWrt AP interfaces configured in:

```text
/etc/presence/presence.conf
```

Example:

```sh
IFACES="wl0-ap0 wl1-ap0"
```

Use:

```sh
iw dev
```

to determine the Wi-Fi interface names used by your OpenWrt device.

Example:

```text
phy#1
        Interface wl1-ap0
                ifindex 20
                type AP

phy#0
        Interface wl0-ap0
                ifindex 15
                type AP
```

---

## 2.4 GHz and 5 GHz with the same SSID

A typical setup uses the same SSID on both radios:

```text
SSID: Home

2.4 GHz -> wl0-ap0
5 GHz   -> wl1-ap0
```

Configure both interfaces:

```sh
IFACES="wl0-ap0 wl1-ap0"
```

Both radios are then treated as part of the same local presence domain.

For example, a client may roam like this:

```text
wl1-ap0 -> AP-STA-DISCONNECTED
wl0-ap0 -> AP-STA-CONNECTED
```

or the events may arrive in the opposite order.

The grace period and the `is_seen_anywhere()` check prevent this normal band transition from being interpreted as the device leaving home.

---

## Additional SSIDs

Additional SSIDs normally create additional AP/BSS interfaces.

Example:

```text
wl0-ap0 -> Home 2.4 GHz
wl1-ap0 -> Home 5 GHz
wl0-ap1 -> Guest 2.4 GHz
```

If clients on the additional SSID should also count as present, add the corresponding interface:

```sh
IFACES="wl0-ap0 wl1-ap0 wl0-ap1"
```

If the additional SSID should not be monitored, do not add its interface.

After adding, removing or changing SSIDs, check the interface layout again:

```sh
iw dev
```

Depending on the device and wireless configuration, BSS interface names may change.

---

## Grace period

Configure the grace period in:

```text
/etc/presence/presence.conf
```

Example:

```sh
GRACE_SECONDS=60
```

The grace period prevents short Wi-Fi interruptions from immediately producing `not_home`.

The basic logic is:

```text
DISCONNECT
    |
    v
wait GRACE_SECONDS
    |
    +-- client visible again --> remain home
    |
    +-- client still absent --> publish not_home
```

A normal roaming event should normally complete much faster than the configured grace period.

If a client continuously moves back and forth between 2.4 GHz and 5 GHz, the WLAN configuration should also be checked rather than simply increasing the grace period indefinitely.

Possible factors include:

- signal overlap
- transmit power
- channel selection
- minimum RSSI settings
- band steering
- client roaming behavior

The roaming decision is ultimately made by the Wi-Fi client, so behavior can differ between devices.

---

## Device configuration

Tracked devices are configured in:

```text
/etc/presence/presence_devices.conf
```

Example:

```text
AA:BB:CC:DD:EE:01 person_one_wifi01_mqtt
AA:BB:CC:DD:EE:02 person_two_wifi01_mqtt
```

MAC address matching is case-insensitive.

The second value is the MQTT topic suffix used for that device.

---

## MQTT topic prefix

A common MQTT topic prefix can be configured in:

```text
/etc/presence/presence.conf
```

Example:

```sh
TOPIC_PREFIX="presence"
```

With:

```text
AA:BB:CC:DD:EE:01 person_one_wifi01_mqtt
```

the resulting MQTT topic becomes:

```text
presence/person_one_wifi01_mqtt
```

If no topic prefix is configured, the topic from `presence_devices.conf` is used directly.

---

## MQTT configuration

Configure the MQTT broker in:

```text
/etc/presence/presence_mqtt.conf
```

Example:

```sh
BROKER="192.168.1.10"
PORT="1883"
USER="openwrt_presence"
PASS="change_me"
QOS="1"
```

Using a dedicated MQTT account for the access point is recommended.

The account only needs permission to publish to the configured presence topics.

If multiple physical OpenWrt access points are used, separate MQTT accounts can also be used for each AP.

---

# Installation

## 1. Copy the files to OpenWrt

The final layout on the router must be:

```text
/etc/presence/
/etc/init.d/presence_hostapd
```

The Presence directory should contain:

```text
/etc/presence/presence_event.sh
/etc/presence/presence.conf
/etc/presence/presence_mqtt.conf
/etc/presence/presence_devices.conf
/etc/presence/install.sh
/etc/presence/healthcheck.sh
```

---

## 2. Configure Presence

Edit:

```text
/etc/presence/presence.conf
```

Example:

```sh
DEBUG=0
GRACE_SECONDS=60

IFACES="wl0-ap0 wl1-ap0"

TOPIC_PREFIX="presence"
```

---

## 3. Configure MQTT

Edit:

```text
/etc/presence/presence_mqtt.conf
```

Example:

```sh
BROKER="192.168.1.10"
PORT="1883"
USER="openwrt_presence"
PASS="change_me"
QOS="1"
```

---

## 4. Configure devices

Edit:

```text
/etc/presence/presence_devices.conf
```

Example:

```text
AA:BB:CC:DD:EE:01 person_one_wifi01_mqtt
AA:BB:CC:DD:EE:02 person_two_wifi01_mqtt
```

---

## 5. Run the installer

Run:

```sh
sh /etc/presence/install.sh
```

The installer installs the required packages, applies file permissions, enables the OpenWrt service and starts it.

Required packages:

```text
hostapd-utils
mosquitto-client-ssl
iw
```

---

# Verify installation

Run:

```sh
sh /etc/presence/healthcheck.sh
```

Example output:

```text
Interfaces: wl0-ap0 wl1-ap0
wl0-ap0: PONG
wl1-ap0: PONG
OK: dependencies present and hostapd control reachable
```

Check the service:

```sh
/etc/init.d/presence_hostapd status
```

Restart it if necessary:

```sh
/etc/init.d/presence_hostapd restart
```

Enable it manually if necessary:

```sh
/etc/init.d/presence_hostapd enable
```

---

# Debug

Enable debugging in:

```text
/etc/presence/presence.conf
```

Set:

```sh
DEBUG=1
```

Restart the service:

```sh
/etc/init.d/presence_hostapd restart
```

Watch Presence logs:

```sh
logread -f | grep presence_event
```

Example:

```text
presence_event: iface=wl1-ap0 event=AP-STA-DISCONNECTED ...
presence_event: start grace timer (60s) ...
presence_event: iface=wl0-ap0 event=AP-STA-CONNECTED ...
presence_event: publish topic='presence/phone' payload='home'
```

During roaming, the exact ordering of CONNECT and DISCONNECT events may vary.

---

## Check hostapd events directly

To test an interface directly:

```sh
hostapd_cli -i wl0-ap0
```

or:

```sh
hostapd_cli -i wl1-ap0
```

You should see events such as:

```text
AP-STA-CONNECTED aa:bb:cc:dd:ee:ff
AP-STA-DISCONNECTED aa:bb:cc:dd:ee:ff
```

---

## Check currently associated clients

To see clients currently connected to an interface:

```sh
iw dev wl0-ap0 station dump
```

or:

```sh
iw dev wl1-ap0 station dump
```

This is also the mechanism used by the Presence script to determine whether a client has reappeared on another configured local radio.

---

# Home Assistant

Use MQTT `device_tracker` entities subscribed to the topics configured in `presence_devices.conf`.

Example `configuration.yaml`:

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

The resulting state is:

```text
home
```

when the OpenWrt AP sees the device, and:

```text
not_home
```

after the configured grace period if the device is no longer present.

---

# Multiple physical access points

`IFACES` only refers to Wi-Fi interfaces on the local OpenWrt device.

Example:

```text
AP downstairs
    wl0-ap0
    wl1-ap0

AP upstairs
    wl0-ap0
    wl1-ap0
```

The downstairs AP cannot determine whether a client is currently associated with the upstairs AP.

For multiple physical access points, use a separate MQTT topic per device and AP.

Example:

```text
presence/person_one/ap_downstairs
presence/person_one/ap_upstairs
```

This creates separate Home Assistant trackers.

For example:

```text
device_tracker.person_one_ap_downstairs
device_tracker.person_one_ap_upstairs
```

Home Assistant can then combine them.

The desired logic is:

```text
AP downstairs = home
AP upstairs   = not_home

Combined      = home
```

or:

```text
AP downstairs = not_home
AP upstairs   = home

Combined      = home
```

Only when both access points report:

```text
not_home
```

should the combined state become:

```text
not_home
```

This keeps the responsibilities separated:

```text
OpenWrt AP
    -> Is this device connected to me?

Home Assistant
    -> Is this device connected to any AP?
```

This is preferable to having multiple independent access points publish conflicting retained states to the same MQTT topic.

---

# Persist across OpenWrt sysupgrade

Add the Presence files to:

```text
/etc/sysupgrade.conf
```

so they are preserved during an OpenWrt upgrade.

Add:

```text
/etc/presence/
/etc/init.d/presence_hostapd
```

You can append them with:

```sh
cat >> /etc/sysupgrade.conf <<'EOF'
/etc/presence/
/etc/init.d/presence_hostapd
EOF
```

Verify:

```sh
cat /etc/sysupgrade.conf
```

Check that the Presence files are included in the sysupgrade backup:

```sh
sysupgrade -l | grep -E 'presence|presence_hostapd'
```

---

## Packages after sysupgrade

The following packages must also be present in the new firmware:

```text
hostapd-utils
mosquitto-client-ssl
iw
```

When using Attended Sysupgrade, make sure these packages are included in the new firmware image.

Keep the configuration during the upgrade.

After upgrading, verify the installation:

```sh
sh /etc/presence/healthcheck.sh
```

Check the service:

```sh
/etc/init.d/presence_hostapd status
```

If necessary:

```sh
/etc/init.d/presence_hostapd enable
/etc/init.d/presence_hostapd restart
```

---

# Design

The project intentionally keeps Presence detection simple.

It uses:

```text
hostapd events
      |
      v
small shell script
      |
      v
MQTT
      |
      v
Home Assistant
```

It does not require:

- periodic SSH polling
- router API polling
- ARP polling
- continuous Wi-Fi scans
- a database
- writes to flash for temporary state

Temporary state is stored in:

```text
/tmp/presence_state
```

which resides in RAM on OpenWrt.

The OpenWrt access point is responsible for determining whether a client is connected to one of its configured radios.

Home Assistant remains responsible for combining Presence information from multiple physical access points.

KISS.
