#!/bin/bash

ART_FILE=zmk/app/boards/shields/nice_view/widgets/art.c
PERIPHERAL_STATUS_FILE=zmk/app/boards/shields/nice_view/widgets/peripheral_status.c

reset_zmk() {
    cd zmk

    # Clean slate repo
    git restore .
    git clean -fd

    cd ..
}

generate_lvgl_img() {
    local name all_caps
    name=$1
    src=$2

    all_caps=$(echo "$name" | tr "[:lower:]" "[:upper:]")

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
    hexdump -s 10 -v -e '"        " 18/1 "0x%02x, " "\n"' "${src}"

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
    preview=$3

    read -d "\t" -r file resize color_convert magick_args \
        <<< $(jq -r ".images[] | select(.name == \"${name}\") | [(.file // false), (.resize // false), (.color_convert // \"none\"), (.magick_args // \"-\")] | @tsv" art/config.json)

    local -a args=("art/$file")

    if [[ "$resize" == "true" ]]; then
        args+=("-resize" "68x140")
    fi

    if [[ "$color_convert" == "monochrome" ]]; then
        args+=("-monochrome")
    elif [[ "$color_convert" == "threshold" ]]; then
        args+=("-threshold" "50%")
    elif [[ "$color_convert" == "h4x4a" ]]; then
        args+=("-colorspace" "Gray" "-ordered-dither" "h4x4a")
    fi

    if [[ ! "$magick_args" == "-" ]]; then
        args+="$magick_args"
    fi

    if [[ "$preview" != "-preview" ]]; then
        args+=("-rotate" "90" "$tmp_dir/$name.pbm")
    else 
        args+=("art/preview/${name}.png")
    fi

    echo ${args[@]}
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

    magick $(magick_args $name "${tmp_dir}" -preview)
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
