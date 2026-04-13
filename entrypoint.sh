#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration variables with environment variable defaults
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

# Function to log messages with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Function to check if device exists
check_device() {
    local device="$1"
    if [[ ! -e "$device" ]]; then
        log "WARNING: Device $device does not exist"
        return 1
    fi
    return 0
}

# Function to start gpsd
start_gpsd() {
    log "Starting GPSD service..."
    
    # Check if GPS device exists
    if ! check_device "$GPS_DEVICE"; then
        log "ERROR: GPS device $GPS_DEVICE not found"
        return 1
    fi
    
    # Check if PPS device exists (optional)
    local pps_arg=""
    if check_device "$PPS_DEVICE"; then
        pps_arg="$PPS_DEVICE"
        log "PPS device found: $PPS_DEVICE"
    else
        log "WARNING: PPS device $PPS_DEVICE not found, continuing without PPS"
    fi
    
    # Build gpsd command
    local gpsd_cmd=("$GPSD_EXECUTABLE")
    
    # Add listen on all addresses if enabled
    [[ "${GPSD_LISTEN_ALL}" == "true" ]] && gpsd_cmd+=("-G")
    
    # Add no-wait option if enabled
    [[ "${GPSD_NO_WAIT}" == "true" ]] && gpsd_cmd+=("-n")
    
    # Add debug level
    gpsd_cmd+=("-D$DEBUG_LEVEL")
    
    # Add control socket
    gpsd_cmd+=("-F" "$GPSD_SOCKET")
    
    # Add GPS speed
    gpsd_cmd+=("-s" "$GPS_SPEED")
    
    # Add GPS device
    gpsd_cmd+=("$GPS_DEVICE")
    
    # Add PPS device if available
    [[ -n "$pps_arg" ]] && gpsd_cmd+=("$pps_arg")
    
    # Add any additional arguments
    gpsd_cmd+=("$@")
    
    log "Executing: ${gpsd_cmd[*]}"
    "${gpsd_cmd[@]}" &
    local gpsd_pid=$!
    log "GPSD started with PID: $gpsd_pid"
    echo "$gpsd_pid" > "$GPSD_PID_FILE"
    
    return 0
}

# Function to start chronyd
start_chronyd() {
    log "Starting Chrony service..."
    
    # Check if chronyd exists
    if [[ ! -x "$CHRONYD_EXECUTABLE" ]]; then
        log "ERROR: chronyd not found at $CHRONYD_EXECUTABLE"
        return 1
    fi

    # Check if chrony user exists
    if ! id -u "$CHRONYD_USER" &>/dev/null; then
        log "ERROR: User '$CHRONYD_USER' does not exist"
        return 1
    fi

    # Confirm correct permissions on chrony run directory
    if [ -d "$CHRONYD_RUN_DIR" ]; then
        chown -R "$CHRONYD_USER:$CHRONYD_USER" "$CHRONYD_RUN_DIR"
        chmod o-rx "$CHRONYD_RUN_DIR"
        # Remove previous pid file if it exists
        rm -f "$CHRONYD_PID_FILE"
    fi

    # Confirm correct permissions on chrony variable state directory
    if [ -d "$CHRONYD_VAR_DIR" ]; then
        chown -R "$CHRONYD_USER:$CHRONYD_USER" "$CHRONYD_VAR_DIR"
    fi

    # Validate LOG_LEVEL (chrony supports 0-3)
    if ! [[ "$LOG_LEVEL" =~ ^[0-3]$ ]]; then
        log "WARNING: Invalid LOG_LEVEL '$LOG_LEVEL', using default (0)"
        LOG_LEVEL=0
    fi

    # Build chronyd command
    local chronyd_cmd=("$CHRONYD_EXECUTABLE")
    
    # Add user
    chronyd_cmd+=("-u" "$CHRONYD_USER")
    
    # Add foreground mode if enabled
    [[ "${CHRONYD_FOREGROUND}" == "true" ]] && chronyd_cmd+=("-d")
    
    # Add system clock control option
    if [[ "${ENABLE_SYSCLK}" == "false" ]]; then
        chronyd_cmd+=("-x")
    fi
    
    # Add log level
    chronyd_cmd+=("-L$LOG_LEVEL")
    
    log "Executing: ${chronyd_cmd[*]}"
    "${chronyd_cmd[@]}" &
    local chronyd_pid=$!
    log "Chronyd started with PID: $chronyd_pid"
    echo "$chronyd_pid" > "$CHRONYD_PID_FILE"
    
    return 0
}

# Function to handle shutdown signals
cleanup() {
    log "Received shutdown signal, cleaning up..."
    
    # Kill chronyd if running
    if [[ -f "$CHRONYD_PID_FILE" ]]; then
        local chronyd_pid=$(cat "$CHRONYD_PID_FILE")
        if kill -0 "$chronyd_pid" 2>/dev/null; then
            log "Stopping chronyd (PID: $chronyd_pid)"
            kill -TERM "$chronyd_pid"
            wait "$chronyd_pid" 2>/dev/null || true
        fi
        rm -f "$CHRONYD_PID_FILE"
    fi
    
    # Kill gpsd if running
    if [[ -f "$GPSD_PID_FILE" ]]; then
        local gpsd_pid=$(cat "$GPSD_PID_FILE")
        if kill -0 "$gpsd_pid" 2>/dev/null; then
            log "Stopping gpsd (PID: $gpsd_pid)"
            kill -TERM "$gpsd_pid"
            wait "$gpsd_pid" 2>/dev/null || true
        fi
        rm -f "$GPSD_PID_FILE"
    fi
    
    log "Cleanup completed"
    exit 0
}

# Function to restart a service
restart_service() {
    local service="$1"
    log "Attempting to restart $service..."
    
    case "$service" in
        "gpsd")
            if start_gpsd; then
                log "$service restarted successfully"
                return 0
            else
                log "Failed to restart $service"
                return 1
            fi
            ;;
        "chronyd")
            if start_chronyd; then
                log "$service restarted successfully"
                return 0
            else
                log "Failed to restart $service"
                return 1
            fi
            ;;
    esac
    
    return 1
}

# Function to wait for services and monitor them
monitor_services() {
    log "Monitoring services (interval: ${MONITOR_INTERVAL}s, restart on failure: ${RESTART_ON_FAILURE})"
    
    while true; do
        local services_failed=false
        
        # Check if gpsd is still running
        if [[ -f "$GPSD_PID_FILE" ]]; then
            local gpsd_pid=$(cat "$GPSD_PID_FILE")
            if ! kill -0 "$gpsd_pid" 2>/dev/null; then
                log "ERROR: GPSD process died unexpectedly"
                services_failed=true
                
                if [[ "${RESTART_ON_FAILURE}" == "true" ]]; then
                    if ! restart_service "gpsd"; then
                        log "Failed to restart GPSD, exiting"
                        cleanup
                        exit 1
                    fi
                else
                cleanup
                exit 1
                fi
            fi
        fi
        
        # Check if chronyd is still running
        if [[ -f "$CHRONYD_PID_FILE" ]]; then
            local chronyd_pid=$(cat "$CHRONYD_PID_FILE")
            if ! kill -0 "$chronyd_pid" 2>/dev/null; then
                log "ERROR: Chronyd process died unexpectedly"
                services_failed=true
                
                if [[ "${RESTART_ON_FAILURE}" == "true" ]]; then
                    if ! restart_service "chronyd"; then
                        log "Failed to restart Chronyd, exiting"
                        cleanup
                        exit 1
                    fi
                else
                cleanup
                exit 1
                fi
            fi
        fi
        
        sleep "$MONITOR_INTERVAL"
    done
}

# Function to display configuration
show_config() {
    log "=== Configuration ==="
    log "GPS Configuration:"
    log "  GPS_DEVICE: $GPS_DEVICE"
    log "  PPS_DEVICE: $PPS_DEVICE"
    log "  GPS_SPEED: $GPS_SPEED"
    log "  DEBUG_LEVEL: $DEBUG_LEVEL"
    log ""
    log "GPSD Configuration:"
    log "  GPSD_EXECUTABLE: $GPSD_EXECUTABLE"
    log "  GPSD_SOCKET: $GPSD_SOCKET"
    log "  GPSD_PID_FILE: $GPSD_PID_FILE"
    log "  GPSD_LISTEN_ALL: $GPSD_LISTEN_ALL"
    log "  GPSD_NO_WAIT: $GPSD_NO_WAIT"
    log ""
    log "Chronyd Configuration:"
    log "  CHRONYD_EXECUTABLE: $CHRONYD_EXECUTABLE"
    log "  CHRONYD_PID_FILE: $CHRONYD_PID_FILE"
    log "  CHRONYD_USER: $CHRONYD_USER"
    log "  CHRONYD_RUN_DIR: $CHRONYD_RUN_DIR"
    log "  CHRONYD_VAR_DIR: $CHRONYD_VAR_DIR"
    log "  CHRONYD_FOREGROUND: $CHRONYD_FOREGROUND"
    log "  ENABLE_SYSCLK: $ENABLE_SYSCLK"
    log "  LOG_LEVEL: $LOG_LEVEL"
    log ""
    log "Timing Configuration:"
    log "  CHRONYD_START_DELAY: ${CHRONYD_START_DELAY}s"
    log "  GPSD_START_DELAY: ${GPSD_START_DELAY}s"
    log "  MONITOR_INTERVAL: ${MONITOR_INTERVAL}s"
    log ""
    log "Monitoring Configuration:"
    log "  ENABLE_MONITORING: $ENABLE_MONITORING"
    log "  RESTART_ON_FAILURE: $RESTART_ON_FAILURE"
    log ""
    log "Runtime Info:"
    log "  User: $(whoami) UID: $(id -u) GID: $(id -g)"
    log "========================"
}

# Main execution
main() {
    log "=== GPS/Chrony Startup Script ==="
    
    # Show configuration
    show_config
    
    # Set up signal handlers
    trap cleanup SIGTERM SIGINT SIGQUIT
    
    # Start chronyd first
    if ! start_chronyd; then
        log "ERROR: Failed to start Chronyd"
        cleanup
        exit 1
    fi

    # Wait before starting GPSD
    log "Waiting ${CHRONYD_START_DELAY}s before starting GPSD..."
    sleep "$CHRONYD_START_DELAY"

    # Now start gpsd
    if ! start_gpsd "$@"; then
        log "ERROR: Failed to start GPSD"
        cleanup
        exit 1
    fi
    
    # Give gpsd a moment to initialize
    log "Waiting ${GPSD_START_DELAY}s for GPSD initialization..."
    sleep "$GPSD_START_DELAY"
    
    log "All services started successfully"

    # Monitor services if enabled
    if [[ "${ENABLE_MONITORING}" == "true" ]]; then
        monitor_services
    else
        log "Service monitoring disabled, using simple wait"
        wait
    fi
}

# Run main function with all arguments
main "$@"