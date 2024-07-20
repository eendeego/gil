#!/bin/bash

set -euo pipefail

this_dir="$(cd "$(dirname "$0")" && pwd)"
firmware_dir="${this_dir}/firmware"
dev_mount="/Volumes/NICENANO"

serial_number() {
    device_path="$(mount | grep "${dev_mount}" | awk '{ print $1 }')"
    device_name="$(basename "${device_path}")"
    system_profiler SPUSBDataType \
        | sed -n '/nice!nano/,/'"${device_name}"'/p' \
        | grep -i 'serial number' \
        | head -n 1 \
        | awk -F ':' '{ print $2 }' \
        | xargs -n 1 echo
}

wait_reset() {
    local half="$1"
    echo "Double click the reset button on the $half half ..."
    while true; do
        if [[ -d "$dev_mount" ]]; then
            break
        fi
        sleep 1
    done
    echo "===> SERIAL NUMBER: $(serial_number)"
}

wait_gone() {
    while [[ -d "$dev_mount" ]]; do
        sleep 1
    done
    sleep 2
}

firmware() {
    local half="$1"
    file="$(find "$firmware_dir" -type f -name '*'"$half"'*.uf2' | head -n 1)"
    if [[ -z "$file" ]]; then
        >&2 echo "ERROR: Firmware for $half half not found. Have you run build.sh?"
        exit 1
    fi
    echo "$file"
}

flash() {
    local half="$1"
    local image="${2:-$half}"
    image="$(firmware "$image")"
    wait_reset "$half"
    echo "Detected $half, using image $image."
    echo "Flashing ..."
    while [[ -d "$dev_mount" ]]; do
        cp "$image" "$dev_mount" > /dev/null 2>&1 || true
    done
    echo "Flashed $half half!"
    wait_gone
}

# flash left reset
# flash right reset
flash left
flash right

