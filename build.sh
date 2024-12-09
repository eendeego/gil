#!/bin/bash

set -euo pipefail

header() {
    local args top_line bottom_line
    args=(${@})
    top_line=1
    bottom_line=1

    # Something something skill issues
    [[ "$1" == "-T" ]] && top_line=0 && shift
    [[ "$1" == "-B" ]] && bottom_line=0 && shift

    if (( $top_line )); then
        echo -e "\n========================================================================"
    fi

    echo == "${@}"

    if (( $bottom_line )); then
        echo -e "========================================================================\n"
    fi
}

this_dir="$(cd "$(dirname "$0")" && pwd)"
config_dir="${this_dir}/config"
fallback_binary="bin"
build_dir="${this_dir}/build"
firmware_dir="${this_dir}/firmware"

cd "$this_dir"

header "Running setup ======================================================="
# This put venv in shell env (amongst other things)
source "$this_dir/setup.sh"

zephyr_version='0.16.3'
zephyr_sdk_path="${this_dir}/zephyr-sdk-${zephyr_version}/"
# zephyr_build='macos-x86_64'
zephyr_build='macos-aarch64'
zephyr_archive="zephyr-sdk-${zephyr_version}_${zephyr_build}.tar.xz"
if [[ ! -d "$zephyr_sdk_path" ]]; then
    header -B "Installing zephyr-sdk ==============================================="

    if [[ ! -f "$zephyr_archive" ]]; then
        header -T -B "  Fetching zephyr-sdk"
        curl -LO "https://github.com/zephyrproject-rtos/sdk-ng/releases/download/v${zephyr_version}/$zephyr_archive"
    fi

    header -T -B "  Untarring zephyr-sdk"
    pv "$zephyr_archive" | tar x

    header -T "Done!"
fi

build_init() {
    # Initialize and update west modules
    if [[ ! -d "${this_dir}/.west" ]]; then
        west init -l "${config_dir}"
        west update
        west zephyr-export
    fi
}

build() {
    local job board shield artifact_name snippet
    job="$1"
    board="$(jq -r '.board' <<<"$job")"
    shield="$(jq -r '.shield' <<<"$job")"
    artifact_name="$(jq -r '.["artifact-name"]' <<<"$job")"
    snippet="$(jq -r '.snippet // empty' <<<"$job")"

    if [[ -n "$artifact_name" ]]; then
        artifact_name="${shield:+$shield-}${board}-zmk"
    fi

    # reset_firmware="settings_reset-${board}-zmk"
    # if [[ "$artifact_name" = "$reset_firmware" ]]; then
    #     if [[ -f "${firmware_dir}/${reset_firmware}.uf2" ]]; then
    #         return
    #     fi
    # fi

    header "Building $artifact_name"

    rm -rf "${build_dir}"
    build_args=(
        -s zmk/app
        -d "${build_dir}"
        -b "${board}"
    )
    if [[ -n "$snippet" ]]; then
        build_args+=( -S "${snippet}" )
    fi
    cmake_args=( "-DZMK_CONFIG=${config_dir}" )
    if [[ -n "$shield" ]]; then
        cmake_args+=( "-DSHIELD=$shield" )
    fi
    if [[ -n "$zmk_load_arg" ]]; then
        cmake_args+=( "${zmk_load_arg}" )
    fi
    build_args+=( -- "${cmake_args[@]}" )
    export ZEPHYR_SDK_INSTALL_DIR="$zephyr_sdk_path"

    header "west build" "${build_args[@]}"
    
    west build "${build_args[@]}"

    mkdir -p "$firmware_dir"
    if [ -f "${build_dir}/zephyr/zmk.uf2" ]; then
        cp "${build_dir}/zephyr/zmk.uf2" "${firmware_dir}/${artifact_name}.uf2"
    elif [ -f "${build_dir}/zephyr/zmk.${fallback_binary}" ]; then
        cp "${build_dir}/zephyr/zmk.${fallback_binary}" "${firmware_dir}/${artifact_name}.${fallback_binary}"
    fi
}

zmk_load_arg=''
if [ -e zephyr/module.yml ]; then
    zmk_load_arg=" -DZMK_EXTRA_MODULES='${this_dir}'"
    new_tmp_dir="${TMPDIR:-/tmp}/zmk-config"
    mkdir -p "${new_tmp_dir}"
    this_dir="${new_tmp_dir}"
    # Copy config files to isolated temporary directory
    >&2 echo "ERROR: Branch not implemented!"; exit 1
fi

header "Building All the things!"

build_init

sh ./patch_art.sh

yaml2json "${this_dir}/build.yaml" \
    | jq -c '.include[]' \
    | while read job
do
    build "$job"
done

header "DONE! ==============================================================="
