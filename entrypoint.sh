#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Captured at entry: fail_exit uses this to satisfy Docker's 10-second
# restart-policy rule (containers that exit sooner are never restarted)
START_TIME=$(date +%s)

###############################################
# Load config.env if present
###############################################
if [[ -f "/config/config.env" ]]; then
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] Loading /config/config.env"
    set -o allexport
    source /config/config.env
    set +o allexport
fi

###############################################
# Configuration variables with defaults
###############################################
GPS_DEVICE="${GPS_DEVICE:-/dev/ttyACM0}"
PPS_DEVICE="${PPS_DEVICE:-/dev/pps0}"
GPS_SPEED="${GPS_SPEED:-115200}"
GPSD_SOCKET="${GPSD_SOCKET:-/var/run/gpsd.sock}"
DEBUG_LEVEL="${DEBUG_LEVEL:-1}"
LOG_LEVEL="${LOG_LEVEL:-0}"

# GPSD configuration
GPSD_EXECUTABLE="${GPSD_EXECUTABLE:-gpsd}"
GPSD_PID_FILE="${GPSD_PID_FILE:-/var/run/gpsd.pid}"
GPSD_LISTEN_ALL="${GPSD_LISTEN_ALL:-true}"
GPSD_NO_WAIT="${GPSD_NO_WAIT:-true}"

# Chronyd configuration
CHRONYD_EXECUTABLE="${CHRONYD_EXECUTABLE:-/usr/sbin/chronyd}"
CHRONYD_PID_FILE="${CHRONYD_PID_FILE:-/var/run/chronyd.pid}"
CHRONYD_USER="${CHRONYD_USER:-chrony}"
CHRONYD_RUN_DIR="${CHRONYD_RUN_DIR:-/run/chrony}"
CHRONYD_VAR_DIR="${CHRONYD_VAR_DIR:-/var/lib/chrony}"
CHRONYD_FOREGROUND="${CHRONYD_FOREGROUND:-true}"
ENABLE_SYSCLK="${ENABLE_SYSCLK:-true}"

# Timing configuration
CHRONYD_START_DELAY="${CHRONYD_START_DELAY:-2}"
GPSD_START_DELAY="${GPSD_START_DELAY:-10}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-5}"

# Monitoring configuration
ENABLE_MONITORING="${ENABLE_MONITORING:-false}"
RESTART_ON_FAILURE="${RESTART_ON_FAILURE:-false}"
DEVICE_WAIT_TIMEOUT="${DEVICE_WAIT_TIMEOUT:-60}"
MAX_RESTART_ATTEMPTS="${MAX_RESTART_ATTEMPTS:-5}"

# PIDs of the supervised daemons (set by start_gpsd/start_chronyd).
# Both daemons run in the foreground so these are the real daemon PIDs.
GPSD_PID=""
CHRONYD_PID=""

###############################################
log() {
    echo "[`date '+%Y-%m-%d %H:%M:%S'`] $*"
}

check_device() {
    local dev="$1"
    if [[ ! -e "$dev" ]]; then
        log "WARNING: Device $dev does not exist"
        return 1
    fi
    return 0
}

# Wait for a device node to appear (USB enumeration and udev can lag the
# container start at boot)
wait_for_device() {
    local dev="$1"
    local waited=0
    while [[ ! -e "$dev" ]]; do
        if (( waited >= DEVICE_WAIT_TIMEOUT )); then
            log "ERROR: Device $dev did not appear within ${DEVICE_WAIT_TIMEOUT}s"
            return 1
        fi
        if (( waited % 10 == 0 )); then
            log "Waiting for device $dev (${waited}/${DEVICE_WAIT_TIMEOUT}s)..."
        fi
        sleep 1
        waited=$((waited + 1))
    done
    return 0
}

# Unrecoverable failure: exit nonzero so Docker's restart policy recreates
# the container (each fresh start re-resolves the devices: mappings, which
# heals a re-enumerated USB device). Docker only honors the restart policy
# if the container was up for at least 10 seconds, so pad the uptime first.
fail_exit() {
    log "FATAL: $*"
    local uptime=$(( $(date +%s) - START_TIME ))
    if (( uptime < 11 )); then
        log "Holding $((11 - uptime))s to satisfy Docker's 10-second restart-policy rule..."
        sleep $((11 - uptime))
    fi
    exit 1
}

###############################################
# Start gpsd
###############################################
start_gpsd() {
    log "Starting GPSD service..."

    check_device "$GPS_DEVICE" || {
        log "ERROR: GPS device $GPS_DEVICE missing"
        return 1
    }

    # Remove a stale control socket left by a previous instance,
    # otherwise gpsd fails to bind it on restart
    rm -f "$GPSD_SOCKET"

    local gpsd_cmd=("$GPSD_EXECUTABLE")

    [[ "$GPSD_LISTEN_ALL" == "true" ]] && gpsd_cmd+=("-G")
    [[ "$GPSD_NO_WAIT" == "true" ]] && gpsd_cmd+=("-n")

    gpsd_cmd+=(
        "-N"                    # foreground: keeps gpsd a direct child so $! is the real PID
        "-b"                    # tolerate USB resets
        "-D$DEBUG_LEVEL"
        "-F" "$GPSD_SOCKET"
        "-s" "$GPS_SPEED"
        "$GPS_DEVICE"
    )

    if check_device "$PPS_DEVICE"; then
        log "PPS device found: $PPS_DEVICE"
        gpsd_cmd+=("$PPS_DEVICE")
    else
        log "WARNING: PPS device missing; running without PPS"
    fi

    log "Executing: ${gpsd_cmd[*]}"
    "${gpsd_cmd[@]}" &

    GPSD_PID=$!
    echo "$GPSD_PID" > "$GPSD_PID_FILE"
    log "GPSD started with PID: $GPSD_PID"
}

###############################################
# Start chronyd
###############################################
start_chronyd() {
    log "Starting Chrony service..."

    [[ -x "$CHRONYD_EXECUTABLE" ]] || {
        log "ERROR: chronyd not found"
        return 1
    }

    id -u "$CHRONYD_USER" >/dev/null 2>&1 || {
        log "ERROR: User $CHRONYD_USER missing"
        return 1
    }

    [[ -d "$CHRONYD_RUN_DIR" ]] && {
        chown -R "$CHRONYD_USER":"$CHRONYD_USER" "$CHRONYD_RUN_DIR"
        chmod o-rx "$CHRONYD_RUN_DIR"
        rm -f "$CHRONYD_PID_FILE"
    }

    [[ -d "$CHRONYD_VAR_DIR" ]] && {
        chown -R "$CHRONYD_USER":"$CHRONYD_USER" "$CHRONYD_VAR_DIR"
    }

    if ! [[ "$LOG_LEVEL" =~ ^[0-3]$ ]]; then
        log "WARNING: Invalid LOG_LEVEL, using default (0)"
        LOG_LEVEL=0
    fi

    local chronyd_cmd=(
        "$CHRONYD_EXECUTABLE"
        "-u" "$CHRONYD_USER"
        "-d"
        "-L$LOG_LEVEL"
    )

    [[ "$ENABLE_SYSCLK" == "false" ]] && chronyd_cmd+=("-x")

    log "Executing: ${chronyd_cmd[*]}"
    "${chronyd_cmd[@]}" &

    CHRONYD_PID=$!
    echo "$CHRONYD_PID" > "$CHRONYD_PID_FILE"
    log "Chronyd started with PID: $CHRONYD_PID"
}

###############################################
# Cleanup
###############################################
cleanup() {
    log "Received shutdown signal, cleaning up..."

    if [[ -n "$CHRONYD_PID" ]]; then
        kill "$CHRONYD_PID" 2>/dev/null || true
    fi

    if [[ -n "$GPSD_PID" ]]; then
        kill "$GPSD_PID" 2>/dev/null || true
    fi

    rm -f "$CHRONYD_PID_FILE" "$GPSD_PID_FILE"

    log "Cleanup completed"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

###############################################
# Monitor services
###############################################
monitor_services() {
    log "Monitoring services..."

    # Consecutive-failure counters: reset whenever a service is seen
    # healthy; when one exceeds MAX_RESTART_ATTEMPTS the container exits
    # so Docker's restart policy can recreate it with fresh device mappings
    local gpsd_failures=0
    local chronyd_failures=0

    while true; do

        if [[ -n "$GPSD_PID" ]] && ! kill -0 "$GPSD_PID" 2>/dev/null; then
            log "ERROR: gpsd died"
            gpsd_failures=$((gpsd_failures + 1))
            if (( gpsd_failures > MAX_RESTART_ATTEMPTS )); then
                fail_exit "gpsd still down after ${MAX_RESTART_ATTEMPTS} restart attempts; exiting so Docker can recreate the container"
            fi
            if [[ "$RESTART_ON_FAILURE" == "true" ]]; then
                if ! start_gpsd; then
                    log "WARNING: gpsd restart failed (attempt ${gpsd_failures}/${MAX_RESTART_ATTEMPTS}); retrying in ${MONITOR_INTERVAL}s"
                fi
            fi
        else
            gpsd_failures=0
        fi

        if [[ -n "$CHRONYD_PID" ]] && ! kill -0 "$CHRONYD_PID" 2>/dev/null; then
            log "ERROR: chronyd died"
            chronyd_failures=$((chronyd_failures + 1))
            if (( chronyd_failures > MAX_RESTART_ATTEMPTS )); then
                fail_exit "chronyd still down after ${MAX_RESTART_ATTEMPTS} restart attempts; exiting so Docker can recreate the container"
            fi
            if [[ "$RESTART_ON_FAILURE" == "true" ]]; then
                if ! start_chronyd; then
                    log "WARNING: chronyd restart failed (attempt ${chronyd_failures}/${MAX_RESTART_ATTEMPTS}); retrying in ${MONITOR_INTERVAL}s"
                fi
            fi
        else
            chronyd_failures=0
        fi

        # Background the sleep so trapped signals (docker stop) are
        # handled immediately instead of after the interval expires
        sleep "$MONITOR_INTERVAL" &
        wait $! || true
    done
}

###############################################
# Configuration display
###############################################
show_config() {
    log "=== Configuration ==="
    log "  GPS_DEVICE: $GPS_DEVICE"
    log "  PPS_DEVICE: $PPS_DEVICE"
    log "  GPS_SPEED: $GPS_SPEED"
    log "  DEBUG_LEVEL: $DEBUG_LEVEL"
    log "  GPSD_SOCKET: $GPSD_SOCKET"
    log "  GPSD_LISTEN_ALL: $GPSD_LISTEN_ALL"
    log "  GPSD_NO_WAIT: $GPSD_NO_WAIT"
    log "  CHRONYD_EXECUTABLE: $CHRONYD_EXECUTABLE"
    log "  CHRONYD_USER: $CHRONYD_USER"
    log "  CHRONYD_RUN_DIR: $CHRONYD_RUN_DIR"
    log "  CHRONYD_VAR_DIR: $CHRONYD_VAR_DIR"
    log "  ENABLE_SYSCLK: $ENABLE_SYSCLK"
    log "  LOG_LEVEL: $LOG_LEVEL"
    log "  CHRONYD_START_DELAY: ${CHRONYD_START_DELAY}s"
    log "  GPSD_START_DELAY: ${GPSD_START_DELAY}s"
    log "  MONITOR_INTERVAL: ${MONITOR_INTERVAL}s"
    log "  ENABLE_MONITORING: $ENABLE_MONITORING"
    log "  RESTART_ON_FAILURE: $RESTART_ON_FAILURE"
    log "  DEVICE_WAIT_TIMEOUT: ${DEVICE_WAIT_TIMEOUT}s"
    log "  MAX_RESTART_ATTEMPTS: $MAX_RESTART_ATTEMPTS"
    log "======================="
}

###############################################
# Main
###############################################
main() {
    log "=== GPS/Chrony Startup Script ==="
    show_config

    start_chronyd || fail_exit "chronyd failed to start"
    sleep "$CHRONYD_START_DELAY"

    wait_for_device "$GPS_DEVICE" || fail_exit "GPS device $GPS_DEVICE not available"
    start_gpsd || fail_exit "gpsd failed to start"
    sleep "$GPSD_START_DELAY"

    log "All services started successfully"

    if [[ "$ENABLE_MONITORING" == "true" ]]; then
        monitor_services
    else
        log "Monitoring disabled; waiting indefinitely"
        wait
    fi
}

main "$@"
