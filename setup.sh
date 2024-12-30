
brew_dir="$(brew --cellar)"
brew_ensure() {
    local package="$1"
    if [[ ! -e "${brew_dir}/${package}" ]] ; then
        if [[ -z "$(brew --prefix "$package" > /dev/null)" ]]; then
            brew install "$package"
            return
        fi
    fi
    echo "-- Found $package"
}

if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    brew_ensure bash
    if [[ "$(bash -c 'echo $BASH_VERSION' | cut -f 1 -d '.')" -ge 4 ]]; then
        exec bash "$0" "$@"
    else
        >&2 echo "ERROR: Bash 4+ is required"
        exit 1
    fi
fi

brew_ensure cmake
brew_ensure ninja
brew_ensure gperf
brew_ensure ccache
brew_ensure qemu
brew_ensure dtc
brew_ensure libmagic
brew_ensure pv
brew_ensure wget
brew_ensure imagemagick
# brew_ensure openocd

if [ ! -f ".venv/bin/activate" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate
pip_ensure() {
    local package="$1"
    if ! pip show "$package" > /dev/null; then
        pip install "$package"
        return
    fi
    echo "-- Found $package"
}
pip_ensure remarshal
pip_ensure west
pip_ensure pyelftools

header() {
    local bar='========================================================================'
    local top="\n${bar}\n"
    local bottom="\n${bar}\n"
    local middle

    while [[ "$1" == -* ]]; do
        case $1 in
            --top|-T) top=''; ;;
            --bottom|-B) bottom=''; ;;
            *) >&2 echo "ERROR: Unknown flag $1"; exit 0; ;;
        esac
        shift
    done
    middle="== ${*}"
    if [[ -n "$top" ]]; then
        middle="${middle} ${bar}"
        middle="${middle:0:${#bar}}"
    fi
    echo -e "${top}${middle}${bottom}"
}

