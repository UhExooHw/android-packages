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

mkdir -p "$TERMUX_TMPDIR" "$TERMUX_CACHEDIR" "$TERMUX_BIN" "$TERMUX_LIB" "$TERMUX_LIB32" "$TERMUX_ETC" "$TERMUX_INCLUDE"

termux_download() {
    local url="$1"
    local output="$2"
    if [ -z "$url" ]; then
        echo "Error: Empty URL provided for download"
        exit 1
    fi
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
    local dirname="$2"
    echo "Extracting $tarfile..."
    mkdir -p "$TERMUX_TMPDIR/$dirname"
    tar -xf "$tarfile" -C "$TERMUX_TMPDIR" || {
        echo "Failed to extract $tarfile"
        exit 1
    }
}

BUSYBOX_VERSION="1.37.0"
BUSYBOX_SRCURL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_PATCHES=(
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0000-use-clang.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0001-clang-fix.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0002-hardcoded-paths-fix.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0003-strchrnul-fix.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0005-no-change-identity.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0006-miscutils-crond.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0007-miscutils-crontab.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0008-networking-ftpd-no-chroot.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0009-networking-httpd-default-port.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0011-networking-tftp-no-chroot.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0012-util-linux-mount-no-addmntent.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0013-busybox-1.36.1-kernel-6.8.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0014-fix-segfault.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0015-fix-ipv6.patch"
    "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0016-fix-ipv6-2.patch"
)
BUSYBOX_CONFIG_URL="https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/busybox.config"

termux_build_busybox() {
    echo "Building busybox..."
    cd "$TERMUX_TMPDIR/busybox-$BUSYBOX_VERSION"

    for patch_url in "${BUSYBOX_PATCHES[@]}"; do
        patch_name=$(basename "$patch_url")
        termux_download "$patch_url" "$TERMUX_CACHEDIR/$patch_name"
        echo "Applying patch $patch_name..."
        patch -p1 < "$TERMUX_CACHEDIR/$patch_name" || {
            echo "Failed to apply patch $patch_name"
            exit 1
        }
    done

    termux_download "$BUSYBOX_CONFIG_URL" "$TERMUX_CACHEDIR/busybox.config"
    sed -e "s|@TERMUX_PREFIX@|$TERMUX_PREFIX|g" \
        -e "s|@TERMUX_SYSROOT@|$TERMUX_STANDALONE_TOOLCHAIN/sysroot|g" \
        -e "s|@TERMUX_HOST_PLATFORM@|${TERMUX_HOST_PLATFORM:-aarch64-linux-android}|g" \
        -e "s|@TERMUX_CFLAGS@|-Wno-ignored-optimization-argument -Wno-unused-command-line-argument|g" \
        -e "s|@TERMUX_LDFLAGS@||g" \
        -e "s|@TERMUX_LDLIBS@|log|g" \
        "$TERMUX_CACHEDIR/busybox.config" > .config
    make oldconfig

    make -j$(nproc)
    install -Dm700 "./0_lib/busybox_unstripped" "$TERMUX_BIN/busybox"
    install -Dm700 "./0_lib/libbusybox.so.${BUSYBOX_VERSION}_unstripped" "$TERMUX_LIB/libbusybox.so.${BUSYBOX_VERSION}"
    ln -sf "$TERMUX_LIB/libbusybox.so.${BUSYBOX_VERSION}" "$TERMUX_LIB/libbusybox.so"
    install -Dm600 -t "$TERMUX_ETC/man/man1" "docs/busybox.1"
    ln -sf "$TERMUX_BIN/busybox" "$TERMUX_BIN/ash"
    ln -sf "$TERMUX_ETC/man/man1/busybox.1" "$TERMUX_ETC/man/man1/ash.1"

    mkdir -p "$TERMUX_LIBexec/busybox"
    for applet in 'less' 'nc' 'vi'; do
        cat > "$TERMUX_LIBexec/busybox/$applet" <<EOF
#!/bin/sh
exec busybox $applet "\$@"
EOF
        chmod 700 "$TERMUX_LIBexec/busybox/$applet"
    done
}

main() {
    echo "Installing build dependencies..."
    pkg_install="pkg_install_$(uname -m)"
    $pkg_install build-essential wget tar patch bzip2

    echo "Downloading sources..."
    termux_download "$BUSYBOX_SRCURL" "$TERMUX_CACHEDIR/busybox-$BUSYBOX_VERSION.tar.bz2"
    termux_extract "$TERMUX_CACHEDIR/busybox-$BUSYBOX_VERSION.tar.bz2" "busybox-$BUSYBOX_VERSION"

    termux_build_busybox

    echo "- Binaries: $TERMUX_BIN"
    echo "- Libraries: $TERMUX_LIB"
    echo "- Libraries (32-bit): $TERMUX_LIB32"
    echo "- Configs: $TERMUX_ETC"
    echo "- Headers: $TERMUX_INCLUDE"
}

pkg_install_aarch64() {
    pkg_install_arm64
}
pkg_install_arm64() {
    pkg update -y && pkg install -y build-essential wget tar patch bzip2 binutils
}

main
