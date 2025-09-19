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

mkdir -p "$TERMUX_TMPDIR" "$TERMUX_CACHEDIR" "$TERMUX_BIN" "$TERMUX_LIB" "$TERMUX_LIB32" "$TERMUX_LIB/pkgconfig" "$TERMUX_ETC" "$TERMUX_INCLUDE"

termux_download() {
    local url="$1"
    local output="$2"
    if [ -z "$url" ]; then
        echo "Error: Empty URL provided for download"
        exit 1
    fi
    if [ ! -f "$output" ]; then
        wget --tries=3 --show-progress -qO "$output" "$url" || {
            echo "Failed to download $url"
            exit 1
        }
    fi
}

termux_extract() {
    local tarfile="$1"
    local dirname="$2"
    mkdir -p "$TERMUX_TMPDIR/$dirname"
    tar -xf "$tarfile" -C "$TERMUX_TMPDIR/$dirname" --strip-components=1 || {
        echo "Failed to extract $tarfile"
        exit 1
    }
}

BUSYBOX_VERSION="1.37.0"
BUSYBOX_SRCURL="https://busybox.net/downloads/busybox-${BUSYBOX_VERSION}.tar.bz2"
BUSYBOX_SHA256="3311dff32e746499f4df0d5df04d7eb396382d7e108bb9250e7b519b837043a4"

termux_build_busybox() {
    cd "$TERMUX_TMPDIR/busybox-$BUSYBOX_VERSION"
    for patch in "$TERMUX_CACHEDIR"/00*.patch; do
        patch -p1 < "$patch" || { echo "Failed to apply $patch"; exit 1; }
    done
    CFLAGS+=" -Wno-ignored-optimization-argument -Wno-unused-command-line-argument"
    sed -e "s|@TERMUX_PREFIX@|/system_ext|g" \
        -e "s|@TERMUX_SYSROOT@||g" \
        -e "s|@TERMUX_HOST_PLATFORM@|aarch64-linux-android|g" \
        -e "s|@TERMUX_CFLAGS@|$CFLAGS|g" \
        -e "s|@TERMUX_LDFLAGS@|$LDFLAGS|g" \
        -e "s|@TERMUX_LDLIBS@|log|g" \
        "$TERMUX_CACHEDIR/busybox.config" > .config
    unset CFLAGS LDFLAGS
    make oldconfig
    make -j$(nproc)
    INSTALL_DIR="$TERMUX_PREFIX/system_ext"
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/share/man/man1" "$INSTALL_DIR/libexec/busybox"
    install -Dm700 "./0_lib/busybox_unstripped" "$INSTALL_DIR/bin/busybox"
    install -Dm700 "./0_lib/libbusybox.so.${BUSYBOX_VERSION}_unstripped" "$INSTALL_DIR/lib/libbusybox.so.${BUSYBOX_VERSION}"
    ln -sfr "$INSTALL_DIR/lib/libbusybox.so.${BUSYBOX_VERSION}" "$INSTALL_DIR/lib/libbusybox.so"
    install -Dm600 -t "$INSTALL_DIR/share/man/man1" "docs/busybox.1"
    ln -sfr "$INSTALL_DIR/bin/busybox" "$INSTALL_DIR/bin/ash"
    ln -sfr "$INSTALL_DIR/share/man/man1/busybox.1" "$INSTALL_DIR/share/man/man1/ash.1"
    local applet
    for applet in 'less' 'nc' 'vi'; do
        {
            echo "#!/system_ext/bin/sh"
            echo "exec busybox $applet \"\$@\""
        } > "$INSTALL_DIR/libexec/busybox/$applet"
        chmod 700 "$INSTALL_DIR/libexec/busybox/$applet"
    done
}

main() {
    pkg_install="pkg_install_$(uname -m)"
    $pkg_install build-essential wget tar patch xz-utils bzip2 binutils
    termux_download "$BUSYBOX_SRCURL" "$TERMUX_CACHEDIR/busybox-$BUSYBOX_VERSION.tar.bz2"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0000-use-clang.patch" "$TERMUX_CACHEDIR/0000-use-clang.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0001-clang-fix.patch" "$TERMUX_CACHEDIR/0001-clang-fix.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0002-hardcoded-paths-fix.patch" "$TERMUX_CACHEDIR/0002-hardcoded-paths-fix.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0003-strchrnul-fix.patch" "$TERMUX_CACHEDIR/0003-strchrnul-fix.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0005-no-change-identity.patch" "$TERMUX_CACHEDIR/0005-no-change-identity.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0006-miscutils-crond.patch" "$TERMUX_CACHEDIR/0006-miscutils-crond.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0007-miscutils-crontab.patch" "$TERMUX_CACHEDIR/0007-miscutils-crontab.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0008-networking-ftpd-no-chroot.patch" "$TERMUX_CACHEDIR/0008-networking-ftpd-no-chroot.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0009-networking-httpd-default-port.patch" "$TERMUX_CACHEDIR/0009-networking-httpd-default-port.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0011-networking-tftp-no-chroot.patch" "$TERMUX_CACHEDIR/0011-networking-tftp-no-chroot.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0012-util-linux-mount-no-addmntent.patch" "$TERMUX_CACHEDIR/0012-util-linux-mount-no-addmntent.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0013-busybox-1.36.1-kernel-6.8.patch" "$TERMUX_CACHEDIR/0013-busybox-1.36.1-kernel-6.8.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0014-fix-segfault.patch" "$TERMUX_CACHEDIR/0014-fix-segfault.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0015-fix-ipv6.patch" "$TERMUX_CACHEDIR/0015-fix-ipv6.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/0016-fix-ipv6-2.patch" "$TERMUX_CACHEDIR/0016-fix-ipv6-2.patch"
    termux_download "https://raw.githubusercontent.com/termux/termux-packages/refs/heads/master/packages/busybox/busybox.config" "$TERMUX_CACHEDIR/busybox.config"
    termux_extract "$TERMUX_CACHEDIR/busybox-$BUSYBOX_VERSION.tar.bz2" "busybox-$BUSYBOX_VERSION"
    termux_build_busybox
    echo "- Binaries: $TERMUX_BIN"
    echo "- Libraries: $TERMUX_LIB"
    echo "- Libraries (32-bit): $TERMUX_LIB32"
    echo "- Configs: $TERMUX_ETC"
    echo "- Headers: $TERMUX_INCLUDE"
    echo "Built files in $TERMUX_PREFIX/system_ext"
}

pkg_install_aarch64() {
    pkg_install_arm64
}
pkg_install_arm64() {
    pkg update -y && pkg install -y build-essential wget tar patch xz-utils bzip2 binutils
}

main
