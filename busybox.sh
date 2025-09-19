#!/bin/bash
set -e

TERMUX_HOME="/data/data/com.termux/files/home"
TERMUX_PREFIX="${TERMUX_HOME}/system"
TERMUX_BIN="${TERMUX_PREFIX}/bin"
TERMUX_LIB="${TERMUX_PREFIX}/lib64"
TERMUX_LIB32="${TERMUX_PREFIX}/lib"
TERMUX_ETC="${TERMUX_PREFIX}/etc"
TERMUX_INCLUDE="${TERMUX_PREFIX}/include"
TERMUX_TMPDIR="${TERMUX_HOME}/tmp"
TERMUX_CACHEDIR="${TERMUX_HOME}/cache"

mkdir -p "$TERMUX_TMPDIR" "$TERMUX_CACHEDIR" "$TERMUX_BIN" "$TERMUX_LIB" "$TERMUX_LIB32" \
         "$TERMUX_LIB/pkgconfig" "$TERMUX_ETC" "$TERMUX_INCLUDE"

termux_download() {
    local url="$1"
    local output="$2"
    if [ ! -f "$output" ]; then
        echo "Downloading $url..."
        wget --tries=3 --show-progress -qO "$output" "$url" || {
            echo "Failed to download $url"
            exit 1
        }
    fi
}

termux_extract() {
    local tarfile="$1"
    echo "Extracting $tarfile..."
    tar -xf "$tarfile" -C "$TERMUX_TMPDIR" || {
        echo "Failed to extract $tarfile"
        exit 1
    }
}

BUSYBOX_VERSION="1.37.0"
BUSYBOX_REVISION="2"
BUSYBOX_SRCURL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_SHA256="f0a5ab1d60796f8aeecc4430ebdc80bd048393ca5c7d07212e72602197f98453"

termux_build_busybox() {
    echo "Building busybox..."
    cd "$TERMUX_TMPDIR/busybox-${BUSYBOX_VERSION}"

    make distclean || true

    make defconfig

    sed -i \
        -e 's/.*CONFIG_STATIC.*/# CONFIG_STATIC is not set/' \
        -e 's/.*CONFIG_FEATURE_INSTALLER.*/CONFIG_FEATURE_INSTALLER=y/' \
        .config

    make -j"$(nproc)"

    make CONFIG_PREFIX="$TERMUX_PREFIX/system_ext" install

    rm -f "$TERMUX_PREFIX/system_ext/bin/rnano" 2>/dev/null || true

    echo "BusyBox build finished."
}

main() {
    echo "Installing build dependencies..."
    pkg_install="pkg_install_$(uname -m)"
    $pkg_install build-essential wget tar bzip2

    echo "Downloading sources..."
    termux_download "$BUSYBOX_SRCURL" "$TERMUX_CACHEDIR/busybox-${BUSYBOX_VERSION}.tar.bz2"

    termux_extract "$TERMUX_CACHEDIR/busybox-${BUSYBOX_VERSION}.tar.bz2"

    termux_build_busybox

    echo "- Binaries: $TERMUX_BIN"
    echo "- Libraries: $TERMUX_LIB"
    echo "- Configs: $TERMUX_ETC"
    echo "- Headers: $TERMUX_INCLUDE"
}

pkg_install_aarch64() {
    pkg_install_arm64
}
pkg_install_arm64() {
    pkg update -y && pkg install -y build-essential wget tar bzip2 xz-utils binutils
}

main
