# OpenWrt Wi-Fi Presence for Home Assistant

Event-driven Wi-Fi presence detection for Home Assistant using OpenWrt, `hostapd` events and MQTT.

The script runs directly on the OpenWrt access point and listens for Wi-Fi client connect/disconnect events from `hostapd`.

No polling of the router from Home Assistant and no remote shell access to OpenWrt are required.

---

## What it does

- Listens to `hostapd` connect/disconnect events on selected AP interfaces
- Publishes retained MQTT state per configured device:
  - `home`
  - `not_home`
- Publishes `home` immediately when a device connects
- Uses a configurable grace period before publishing `not_home`
- Checks all configured local Wi-Fi interfaces before declaring a device absent
- Handles normal roaming between 2.4 GHz and 5 GHz radios
- Stores temporary state in `/tmp` (RAM)
- Uses MQTT to provide the resulting state to Home Assistant

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

### Connect

When `hostapd` reports:

```text
AP-STA-CONNECTED
```

the script immediately publishes:

```text
home
```

Any pending disconnect grace period for that device is cancelled.

### Disconnect

When `hostapd` reports:

```text
AP-STA-DISCONNECTED
```

the script starts the configured grace timer.

After the grace period, it checks whether the device is visible on any configured local Wi-Fi interface.

```text
DISCONNECT
    |
    v
wait GRACE_SECONDS
    |
    +-- device visible again --> suppress not_home
    |
    +-- device still absent --> publish not_home
```

This prevents normal Wi-Fi roaming or short reconnects from being interpreted as the device leaving home.

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
    Checks dependencies and hostapd control sockets

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

to determine the AP interface names on your OpenWrt device.

Example:

```text
phy#1
        Interface wl1-ap0
                type AP

phy#0
        Interface wl0-ap0
                type AP
```

Only interfaces listed in `IFACES` are monitored.

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

During normal roaming, events may look like:

```text
wl1-ap0 -> AP-STA-DISCONNECTED
wl0-ap0 -> AP-STA-CONNECTED
```

The exact event order may vary.

The grace period and the check across all configured interfaces prevent such a band transition from being interpreted as `not_home`.

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

After adding, removing or changing SSIDs, verify the interface layout again:

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

The grace period is intended to absorb:

- normal roaming between radios
- short Wi-Fi disconnects
- reassociation
- temporary disappearance from the station table

A normal roaming event should usually complete much faster than the grace period.

If a client continuously moves back and forth between 2.4 GHz and 5 GHz, the WLAN configuration should also be checked instead of simply increasing the grace period indefinitely.

Possible factors include signal overlap, transmit power, channel selection, band steering and the roaming behavior of the client itself.

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

The second value is the MQTT topic or topic suffix assigned to that device.

---

## MQTT topic prefix

A common prefix can be configured in:

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

the resulting topic becomes:

```text
presence/person_one_wifi01_mqtt
```

If no prefix is configured, the value from `presence_devices.conf` is used directly.

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

The account only needs permission to publish to the required presence topics.

---

# Installation

## 1. Copy the files to OpenWrt

The final file layout on the router must be:

```text
/etc/presence/presence_event.sh
/etc/presence/presence.conf
/etc/presence/presence_mqtt.conf
/etc/presence/presence_devices.conf
/etc/presence/install.sh
/etc/presence/healthcheck.sh
/etc/init.d/presence_hostapd
```

---

## 2. Configure the installation

Edit:

```text
/etc/presence/presence.conf
/etc/presence/presence_mqtt.conf
/etc/presence/presence_devices.conf
```

At minimum, verify:

```sh
IFACES="wl0-ap0 wl1-ap0"
GRACE_SECONDS=60
```

and configure the MQTT broker and devices.

---

## 3. Run the installer

```sh
sh /etc/presence/install.sh
```

The installer installs the required packages, applies permissions, enables the service and starts it.

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

Example:

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

Enable logging in:

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

Watch the log:

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

The exact CONNECT/DISCONNECT order during roaming may vary.

---

## Check hostapd events directly

To monitor one AP interface directly:

```sh
hostapd_cli -i wl0-ap0
```

or:

```sh
hostapd_cli -i wl1-ap0
```

Events should look similar to:

```text
AP-STA-CONNECTED aa:bb:cc:dd:ee:ff
AP-STA-DISCONNECTED aa:bb:cc:dd:ee:ff
```

This is useful when diagnosing whether an event is generated by `hostapd` before looking at MQTT or Home Assistant.

---

## Check associated clients

To see which clients are currently associated with an interface:

```sh
iw dev wl0-ap0 station dump
```

or:

```sh
iw dev wl1-ap0 station dump
```

The Presence script uses the same station information to determine whether a device has appeared on another configured local radio.

---

# Home Assistant

Create MQTT `device_tracker` entities for the configured topics.

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

The tracker reports `home` while the OpenWrt access point sees the device and `not_home` after the grace period when it is no longer present.

---

# Multiple physical access points

`IFACES` only covers radios on the local OpenWrt device.

Example:

```text
AP downstairs
    wl0-ap0
    wl1-ap0

AP upstairs
    wl0-ap0
    wl1-ap0
```

One OpenWrt AP cannot determine whether the client is currently associated with another physical AP.

For multiple physical APs, use a separate MQTT topic and Home Assistant tracker for each AP.

Example:

```text
presence/person_one/ap_downstairs
presence/person_one/ap_upstairs
```

Then combine the resulting trackers in Home Assistant.

The desired logic is:

```text
any AP = home
    -> combined presence = home

all APs = not_home
    -> combined presence = not_home
```

This keeps the responsibilities clear:

```text
OpenWrt AP
    -> Is this device connected to me?

Home Assistant
    -> Is this device connected to any AP?
```

Avoid having multiple independent APs publish competing retained states to the same MQTT topic.

Separate MQTT accounts may also be used for each physical AP.

---

# Persist across OpenWrt sysupgrade

Add the Presence files to:

```text
/etc/sysupgrade.conf
```

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

Check that the Presence files are included in the backup:

```sh
sysupgrade -l | grep -E 'presence|presence_hostapd'
```

---

## Packages after sysupgrade

The configuration files can be preserved by OpenWrt, but the required packages must also exist in the new firmware:

```text
hostapd-utils
mosquitto-client-ssl
iw
```

When using Attended Sysupgrade, make sure these packages are included in the new firmware image and keep the configuration during the upgrade.

After upgrading:

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

The project intentionally keeps presence detection simple:

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

It does not require periodic SSH polling, router API polling, ARP polling, continuous Wi-Fi scans or a database.

Temporary runtime state is stored in:

```text
/tmp/presence_state
```

and therefore remains in RAM instead of creating unnecessary flash writes.

OpenWrt determines whether a device is present on its configured local radios.

Home Assistant can combine the resulting presence states when multiple physical access points are used.

KISS.
