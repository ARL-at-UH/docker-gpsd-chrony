#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration variables
# ---------------------------------------------------------------------------

GPS_DEVICE="${GPS_DEVICE:-/dev/ttyACM0}"
PPS_DEVICE="${PPS_DEVICE:-/dev/pps0}"
GPS_SPEED="${GPS_SPEED:-38400}"
GPSD_SOCKET="${GPSD_SOCKET:-/var/run/gpsd.sock}"
DEBUG_LEVEL="${DEBUG_LEVEL:-1}"
LOG_LEVEL="${LOG_LEVEL:-0}"
RESTART_ON_FAILURE="${RESTART_ON_FAILURE:-true}"
MONITOR_INTERVAL="${MONITOR_INTERVAL:-5}"
GPSD_EXECUTABLE="${GPSD_EXECUTABLE:-gpsd}"

# ---------------------------------------------------------------------------
# Logging helper
# ---------------------------------------------------------------------------

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# ---------------------------------------------------------------------------
# Device existence check
# ---------------------------------------------------------------------------

check_device() {
    [[ -e "$1" ]]
}

# ---------------------------------------------------------------------------
# Start gpsd
# ---------------------------------------------------------------------------

start_gpsd() {
    log "Starting gpsd..."

    if ! check_device "$GPS_DEVICE"; then
        log "ERROR: GPS device $GPS_DEVICE does not exist."
        return 1
    fi

    local gpsd_cmd=(
        "$GPSD_EXECUTABLE"
        -b              # Handle USB resets gracefully
        -G              # Allow remote access
        -n              # Do not wait for clients
        -D"$DEBUG_LEVEL"
        -F "$GPSD_SOCKET"
        -s "$GPS_SPEED"
        "$GPS_DEVICE"
    )

    if check_device "$PPS_DEVICE"; then
        log "PPS device detected: $PPS_DEVICE"
        gpsd_cmd+=("$PPS_DEVICE")
    else
        log "No PPS device found; continuing without PPS."
    fi

    log "Executing: ${gpsd_cmd[*]}"
    "${gpsd_cmd[@]}" &

    local pid=$!
    echo "$pid" >/var/run/gpsd.pid
    log "gpsd started with PID $pid"
}

# ---------------------------------------------------------------------------
# Start chronyd
# ---------------------------------------------------------------------------

start_chronyd() {
    log "Starting chronyd..."

    if [[ ! -x "/usr/sbin/chronyd" ]]; then
        log "ERROR: chronyd not found."
        return 1
    fi

    local chronyd_cmd=(
        /usr/sbin/chronyd
        -u chrony
        -d
        -L"$LOG_LEVEL"
    )

    log "Executing: ${chronyd_cmd[*]}"
    "${chronyd_cmd[@]}" &

    local pid=$!
    echo "$pid" >/var/run/chronyd.pid
    log "chronyd started with PID $pid"
}

# ---------------------------------------------------------------------------
# GPSD HEALTH CHECK
# ---------------------------------------------------------------------------

is_gpsd_healthy() {
    local pid_file="/var/run/gpsd.pid"

    # PID must exist
    if [[ ! -f "$pid_file" ]]; then
        return 1
    fi

    local pid
    pid=$(cat "$pid_file")

    if ! kill -0 "$pid" 2>/dev/null; then
        return 1
    fi

    # Confirm gpsd responds on control socket
    if ! timeout 2 gpspipe -w -n 1 >/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# ---------------------------------------------------------------------------
# CLEANUP HANDLER
# ---------------------------------------------------------------------------

cleanup() {
    log "Shutting down services..."

    if [[ -f /var/run/chronyd.pid ]]; then
        kill "$(cat /var/run/chronyd.pid)" 2>/dev/null || true
        rm -f /var/run/chronyd.pid
    fi

    if [[ -f /var/run/gpsd.pid ]]; then
        kill "$(cat /var/run/gpsd.pid)" 2>/dev/null || true
        rm -f /var/run/gpsd.pid
    fi

    log "Cleanup done."
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

# ---------------------------------------------------------------------------
# MONITORING LOOP
# ---------------------------------------------------------------------------

monitor_services() {
    log "Monitoring services every ${MONITOR_INTERVAL}s..."

    while true; do
        if ! is_gpsd_healthy; then
            log "ERROR: gpsd failed health check."

            if [[ "$RESTART_ON_FAILURE" == "true" ]]; then
                log "Restarting gpsd..."
                start_gpsd
                sleep 3
            else
                cleanup
                exit 1
            fi
        fi

        sleep "$MONITOR_INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Main Flow
# ---------------------------------------------------------------------------

log "=== Starting GPS + Chrony Container ==="
log "GPS device: $GPS_DEVICE"
log "PPS device: $PPS_DEVICE"
log "Restart on failure: $RESTART_ON_FAILURE"

start_chronyd
sleep 2

start_gpsd
sleep 5

log "Services started."

monitor_services