#!/bin/bash

set -euo pipefail

this_dir="$(cd "$(dirname "$0")" && pwd)"
widgets_dir="${this_dir}/zmk/app/boards/shields/nice_view/widgets"
ART_FILE="${widgets_dir}/art.c"
PERIPHERAL_STATUS_FILE="${widgets_dir}/peripheral_status.c"

IMG_SIZE="68x140"

reset_zmk() {
    cd "${this_dir}/zmk"

    # Clean slate repo
    git restore .
    git clean -fd

    cd ..
}

generate_lvgl_img() {
    local name=$1
    local src=$2

    local all_caps=$(tr "[:lower:]" "[:upper:]" <<<"$name")

    cat <<EOF
#ifndef LV_ATTRIBUTE_IMG_${all_caps}
#define LV_ATTRIBUTE_IMG_${all_caps}
#endif

const LV_ATTRIBUTE_MEM_ALIGN LV_ATTRIBUTE_LARGE_CONST LV_ATTRIBUTE_IMG_${all_caps} uint8_t ${name}_map[] = {
#if CONFIG_NICE_VIEW_WIDGET_INVERTED
        0xff, 0xff, 0xff, 0xff, /*Color of index 0*/
        0x00, 0x00, 0x00, 0xff, /*Color of index 1*/
#else
        0x00, 0x00, 0x00, 0xff, /*Color of index 0*/
        0xff, 0xff, 0xff, 0xff, /*Color of index 1*/
#endif
EOF
    # Skip 10 bytes (header), write as C code
    hexdump -s 10 -v -e '"        " 18/1 "0x%02x, " "\n"' "${src}" | sed -e 's/0x  /0xff/g'

    cat <<EOF
};

const lv_img_dsc_t ${name} = {
  .header.cf = LV_IMG_CF_INDEXED_1BIT,
  .header.always_zero = 0,
  .header.reserved = 0,
  .header.w = 140,
  .header.h = 68,
  .data_size = 1232,
  .data = ${name}_map,
};
EOF
}

magick_args() {
    local name tmp_dir preview file resize color_convert magick_args
    name=$1
    tmp_dir=$2
    preview=${3-code}

    # This read always returns with exit code 1
    # Use `if` trick from https://stackoverflow.com/a/67066283/543452
    if read  -d "\t" -r file resize color_convert magick_args; then :; fi \
        <<< $(jq -r ".images[] | select(.name == \"${name}\") | [(.file // false), (.resize // false), (.color_convert // \"none\"), (.magick_args // \"-\")] | @tsv" art/config.json)

    local -a args=("art/$file")

    if [[ "$resize" == "proportional" ]]; then
        # Image is expected to be proportional to 68x140

        local size_modulus
        size_modulus=$(file "art/$file" | perl -p -e 's/.*?\s(\d+)\sx\s(\d+).*/($1\*140)%($2*68)/g' | bc)

        if [[ "$size_modulus" != "0" ]]; then
            local size
            size=$(file "art/$file" | perl -p -e 's/.*?\s(\d+\sx\s\d+).*/$1/g')
            echo Image size \(${size}\) not proportional to 68x140. Use either \"ignoreAspectRatio\", or \"fill\" resize strategy instead. >&2
            exit 1
        fi

        args+=("-resize" "${IMG_SIZE}")
    elif [[ "$resize" == "ignoreAspectRatio" ]]; then
        # Image will be distorted
        args+=("-resize" "${IMG_SIZE}!")
    elif [[ "$resize" == "fill" ]]; then
        # Resize the image based on the smallest fitting dimension 
        args+=("-resize" "${IMG_SIZE}^" "-gravity" "center" "-extent" "${IMG_SIZE}")
    else
        local size
        size=$(file "art/$file" | perl -p -e 's/.*?\s(\d+\sx\s\d+).*/$1/g')
        if [[ "$size" != "68 x 140" ]]; then
            echo Invalid image size: "${size}". Use \"resize\" to set a resize strategy. >&2
            echo Available resize strategies: \"proportional\", \"ignoreAspectRatio\", \"fill\" >&2
            exit 1
        fi
    fi

    if [[ "$color_convert" == "monochrome" ]]; then
        args+=("-monochrome")
    elif [[ "$color_convert" == "threshold" ]]; then
        args+=("-threshold" "50%")
    elif [[ "$color_convert" == "h4x4a" ]]; then
        args+=("-colorspace" "Gray" "-ordered-dither" "h4x4a")
    fi

    if [[ ! "$magick_args" == "-" ]]; then
        args+=("$magick_args")
    fi

    if [[ "$preview" != "-preview" ]]; then
        args+=("-rotate" "90" "$tmp_dir/$name.pbm")
    else 
        args+=("art/preview/${name}.png")
    fi

    echo "${args[@]}"
}

reset_zmk

cat >>$ART_FILE <<EOF

/********************************************************************************
 * Gil Images
 */

EOF

tmp_dir="${TMPDIR:-/tmp}/gil-art"
mkdir -p "${tmp_dir}"
mkdir -p art/preview

# For testing only
# magick $(magick_args "test_pattern_04c" "${tmp_dir}" -preview)
# exit

# # Preview all images, which is useful when testing stuff
# jq -r '.images[] | .name' art/config.json \
#     | while read line
# do
#     read -d "\t" -r name <<< $(echo "${line}")
#     magick $(magick_args $name "${tmp_dir}" -preview)
# done

# Only generate C source for the selected ones
jq -r '.display[]' art/config.json \
    | while read line
do
    read -r name <<< $(echo "${line}")

    # Call magick_args separately, otherwize `magick` will still run
    declare -a preview_args
    preview_args=$(magick_args $name "${tmp_dir}" -preview)

    magick $(magick_args $name "${tmp_dir}" -preview)
    magick ${preview_args[@]}
    magick $(magick_args $name "${tmp_dir}")
    generate_lvgl_img $name "$tmp_dir/$name.pbm" >> $ART_FILE
done

# Feeling lazy here...

display_len=$(jq -r '.display | length' art/config.json)

if [[ "$display_len" == "0" ]]; then
    echo "Need at least one image!"
    exit 1
elif [[ "$display_len" == "1" ]]; then
    img0=$(jq -r '.display[0]' art/config.json)
    img1="$img0"
elif [[ "$display_len" == "2" ]]; then
    img0=$(jq -r '.display[0]' art/config.json)
    img1=$(jq -r '.display[1]' art/config.json)
else
    echo "No support for display larger than 2 images"
fi

perl -pi -e "s/balloon/$img0/g" $PERIPHERAL_STATUS_FILE
perl -pi -e "s/mountain/$img1/g" $PERIPHERAL_STATUS_FILE
