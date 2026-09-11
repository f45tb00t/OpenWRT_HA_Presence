#!/bin/sh
set -eu

# This script is invoked by hostapd_cli -a as:
#   presence_event.sh <iface> <event> <mac> [extra...]

CONF="/etc/presence/presence.conf"
MQTT_CONF="/etc/presence/presence_mqtt.conf"
DEV_CONF="/etc/presence/presence_devices.conf"

[ -f "$CONF" ] || exit 0
[ -f "$MQTT_CONF" ] || exit 0
[ -f "$DEV_CONF" ] || exit 0

# shellcheck disable=SC1090
. "$CONF"
# shellcheck disable=SC1090
. "$MQTT_CONF"

LOGTAG="presence_event"
log() {
  [ "${DEBUG:-0}" -eq 1 ] || return 0
  logger -t "$LOGTAG" "$*"
}

HOST_ID="$(cat /proc/sys/kernel/hostname 2>/dev/null || echo openwrt)"
STATE_DIR="/tmp/presence_state"
mkdir -p "$STATE_DIR"

IFACE="${1:-}"
EVENT="${2:-}"
shift 2 || true
REST="$*"

# Extract MAC with colons from the remaining args
# (hostapd_cli may append key=value tokens)
MAC_RAW="$(
  printf '%s\n' "$REST" \
    | grep -Eoi '([0-9a-f]{2}:){5}[0-9a-f]{2}' \
    | head -n 1 \
    || true
)"

MAC="$(printf '%s' "$MAC_RAW" | tr '[:lower:]' '[:upper:]')"

log "iface=$IFACE event=$EVENT rest='$REST' mac='$MAC'"

# Ignore events without a MAC
# (e.g. EAPOL-4WAY-HS-COMPLETED without args on some builds)
[ -n "$MAC" ] || exit 0

STATE_FILE="$STATE_DIR/${MAC}.state"

# Map MAC -> topic (case-insensitive)
TOPIC="$(
  awk -v m="$MAC" '
    BEGIN {
      mm = toupper(m)
    }

    /^[[:space:]]*#/ {
      next
    }

    NF >= 2 {
      if (toupper($1) == mm) {
        print $2
        exit
      }
    }
  ' "$DEV_CONF"
)"

log "mapped mac=$MAC -> topic='$TOPIC'"
[ -n "$TOPIC" ] || exit 0

# Enrich TOPIC with prefix
[ -n "${TOPIC_PREFIX:-}" ] && TOPIC="${TOPIC_PREFIX%/}/$TOPIC"

publish() {
  payload="$1"

  log "publish topic='$TOPIC' payload='$payload'"

  mosquitto_pub \
    -h "$BROKER" \
    -p "$PORT" \
    -u "$USER" \
    -P "$PASS" \
    -I "ap-presence-$HOST_ID-" \
    -q "${QOS:-1}" \
    -r \
    --keepalive 30 \
    --will-topic "${TOPIC}/status" \
    --will-payload "unknown" \
    --will-retain \
    -t "$TOPIC" \
    -m "$payload" \
    >/dev/null
}

is_seen_anywhere() {
  # Roaming check across local radios on the same AP
  for i in ${IFACES:-}; do
    if iw dev "$i" station dump 2>/dev/null \
      | awk '/^Station/ {print toupper($2)}' \
      | grep -Fxq "$MAC"; then
      return 0
    fi
  done

  return 1
}

case "$EVENT" in
  AP-STA-CONNECTED)
    # Cancel any pending grace timer and publish home immediately
    rm -f "$STATE_FILE" 2>/dev/null || true

    log "mac=$MAC connected -> publish home"
    publish "home"
    ;;

  AP-STA-DISCONNECTED)
    # Each disconnect gets its own token.
    # $$ is the PID of this event handler process.
    TOKEN="$$-$(date +%s)"

    printf '%s\n' "$TOKEN" > "$STATE_FILE"

    log "start grace timer (${GRACE_SECONDS:-0}s) for mac=$MAC token=$TOKEN"

    (
      sleep "${GRACE_SECONDS:-0}"

      # Check whether this timer still owns the current state.
      CURRENT_TOKEN="$(cat "$STATE_FILE" 2>/dev/null || true)"

      if [ "$CURRENT_TOKEN" != "$TOKEN" ]; then
        log "mac=$MAC grace timer superseded -> ignore stale timer token=$TOKEN"
        exit 0
      fi

      # Client may have roamed or reconnected without the old timer
      # having seen its CONNECT event yet.
      if is_seen_anywhere; then
        log "mac=$MAC reappeared during grace -> suppress not_home"

        # Only remove the state if it still belongs to this timer.
        CURRENT_TOKEN="$(cat "$STATE_FILE" 2>/dev/null || true)"

        if [ "$CURRENT_TOKEN" = "$TOKEN" ]; then
          rm -f "$STATE_FILE" 2>/dev/null || true
        fi

        exit 0
      fi

      # Check again because a CONNECT or another DISCONNECT may have
      # happened while checking the radios.
      CURRENT_TOKEN="$(cat "$STATE_FILE" 2>/dev/null || true)"

      if [ "$CURRENT_TOKEN" != "$TOKEN" ]; then
        log "mac=$MAC state changed during grace check -> suppress not_home"
        exit 0
      fi

      log "grace expired for mac=$MAC -> publish not_home"

      rm -f "$STATE_FILE" 2>/dev/null || true
      publish "not_home"
    ) &
    ;;

  *)
    # Ignore other events
    exit 0
    ;;
esac

exit 0
