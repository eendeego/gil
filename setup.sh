
brew_dir="$(dirname "$(brew --cellar)")"
brew_ensure() {
    local package="$1"
    if [[ -e "${brew_dir}/${package}" ]] ; then
        if ! brew --prefix "$package" > /dev/null; then
            brew install "$package"
        fi
    fi
}
brew_ensure cmake
brew_ensure ninja
brew_ensure gperf
brew_ensure ccache
brew_ensure qemu
brew_ensure dtc
brew_ensure libmagic
brew_ensure wget
# brew_ensure openocd

if [ ! -f ".venv/bin/activate" ]; then
    python3 -m venv .venv
fi
source .venv/bin/activate
pip_ensure() {
    local package="$1"
    if ! pip show "$package" > /dev/null; then
        pip install "$package"
    fi
}
pip_ensure remarshal
pip_ensure west
pip_ensure pyelftools
