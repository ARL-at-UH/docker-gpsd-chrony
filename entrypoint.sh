#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

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

###############################################
# Start gpsd (corrected logic)
###############################################
start_gpsd() {
    log "Starting GPSD service..."

    check_device "$GPS_DEVICE" || {
        log "ERROR: GPS device $GPS_DEVICE missing"
        return 1
    }

    local gpsd_cmd=("$GPSD_EXECUTABLE")

    [[ "$GPSD_LISTEN_ALL" == "true" ]] && gpsd_cmd+=("-G")
    [[ "$GPSD_NO_WAIT" == "true" ]] && gpsd_cmd+=("-n")

    gpsd_cmd+=(
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

    local pid=$!
    echo "$pid" > "$GPSD_PID_FILE"
    log "GPSD started with PID: $pid"
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

    local pid=$!
    echo "$pid" > "$CHRONYD_PID_FILE"
    log "Chronyd started with PID: $pid"
}

###############################################
# Cleanup
###############################################
cleanup() {
    log "Received shutdown signal, cleaning up..."

    if [[ -f "$CHRONYD_PID_FILE" ]]; then
        kill "$(cat "$CHRONYD_PID_FILE")" 2>/dev/null || true
        rm -f "$CHRONYD_PID_FILE"
    fi

    if [[ -f "$GPSD_PID_FILE" ]]; then
        kill "$(cat "$GPSD_PID_FILE")" 2>/dev/null || true
        rm -f "$GPSD_PID_FILE"
    fi

    log "Cleanup completed"
    exit 0
}

trap cleanup SIGTERM SIGINT SIGQUIT

###############################################
# Monitor services (unchanged but simple PID check only)
###############################################
monitor_services() {
    log "Monitoring services..."

    while true; do

        if [[ -f "$GPSD_PID_FILE" ]]; then
            local pid=$(cat "$GPSD_PID_FILE")
            if ! kill -0 "$pid" 2>/dev/null; then
                log "ERROR: gpsd died"
                [[ "$RESTART_ON_FAILURE" == "true" ]] && start_gpsd
            fi
        fi

        if [[ -f "$CHRONYD_PID_FILE" ]]; then
            local pid=$(cat "$CHRONYD_PID_FILE")
            if ! kill -0 "$pid" 2>/dev/null; then
                log "ERROR: chronyd died"
                [[ "$RESTART_ON_FAILURE" == "true" ]] && start_chronyd
            fi
        fi

        sleep "$MONITOR_INTERVAL"
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
    log "======================="
}

###############################################
# Main
###############################################
main() {
    log "=== GPS/Chrony Startup Script ==="
    show_config

    start_chronyd
    sleep "$CHRONYD_START_DELAY"

    start_gpsd
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