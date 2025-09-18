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

LIBICONV_VERSION="1.18"
LIBICONV_SRCURL="https://mirrors.kernel.org/gnu/libiconv/libiconv-$LIBICONV_VERSION.tar.gz"
LIBICONV_CONFIGURE_ARGS="--enable-extra-encodings --prefix=/system_ext --includedir=/system_ext/include --libdir=/system_ext/lib64"

NCURSES_SNAPSHOT_COMMIT="a480458efb0662531287f0c75116c0e91fe235cb"
NCURSES_VERSION="6.5.20240831"
NCURSES_SRCURL="https://github.com/ThomasDickey/ncurses-snapshots/archive/$NCURSES_SNAPSHOT_COMMIT.tar.gz"
NCURSES_CONFIGURE_ARGS="
ac_cv_header_locale_h=no
am_cv_langinfo_codeset=no
--disable-opaque-panel
--disable-stripping
--enable-const
--enable-ext-colors
--enable-ext-mouse
--enable-overwrite
--enable-pc-files
--enable-termcap
--enable-widec
--mandir=/system_ext/man
--includedir=/system_ext/include
--with-pkg-config-libdir=/system_ext/lib64/pkgconfig
--with-static
--with-shared
--with-termpath=/system_ext/etc/termcap
--prefix=/system_ext
"

NANO_VERSION="8.6"
NANO_SRCURL="https://nano-editor.org/dist/latest/nano-$NANO_VERSION.tar.xz"
NANO_CONFIGURE_ARGS="
ac_cv_header_glob_h=no
ac_cv_header_pwd_h=no
gl_cv_func_strcasecmp_works=yes
--disable-libmagic
--enable-utf8
--with-wordbounds
--prefix=/system_ext
--includedir=/system_ext/include
--libdir=/system_ext/lib64
"

termux_build_libiconv() {
    echo "Building libiconv..."
    cd "$TERMUX_TMPDIR/libiconv-$LIBICONV_VERSION"
    ./configure $LIBICONV_CONFIGURE_ARGS
    make -j$(nproc)
    make install DESTDIR="$TERMUX_PREFIX"
}

termux_build_ncurses() {
    echo "Building ncurses..."
    cd "$TERMUX_TMPDIR/ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT"
    export CPPFLAGS="-fPIC"
    ./configure $NCURSES_CONFIGURE_ARGS
    make -j$(nproc)
    make install DESTDIR="$TERMUX_PREFIX"

    cd "$TERMUX_LIB" || { echo "Failed to access $TERMUX_LIB"; exit 1; }
    for lib in form menu ncurses panel; do
        ln -sf "lib${lib}w.so.${NCURSES_VERSION:0:3}" "lib${lib}.so.${NCURSES_VERSION:0:3}"
        ln -sf "lib${lib}w.so.${NCURSES_VERSION:0:3}" "lib${lib}.so.${NCURSES_VERSION:0:1}"
        ln -sf "lib${lib}w.so.${NCURSES_VERSION:0:3}" "lib${lib}.so"
        ln -sf "lib${lib}w.a" "lib${lib}.a"
        ln -sf "${lib}w.pc" "pkgconfig/$lib.pc" || { echo "Failed to create symlink for $lib.pc"; exit 1; }
    done
    for lib in curses termcap tic tinfo; do
        ln -sf "libncursesw.so.${NCURSES_VERSION:0:3}" "lib${lib}.so.${NCURSES_VERSION:0:3}"
        ln -sf "libncursesw.so.${NCURSES_VERSION:0:3}" "lib${lib}.so.${NCURSES_VERSION:0:1}"
        ln -sf "libncursesw.so.${NCURSES_VERSION:0:3}" "lib${lib}.so"
        ln -sf "libncursesw.a" "lib${lib}.a"
        ln -sf "ncursesw.pc" "pkgconfig/$lib.pc" || { echo "Failed to create symlink for $lib.pc"; exit 1; }
    done

    cd "$TERMUX_INCLUDE" || { echo "Failed to access $TERMUX_INCLUDE"; exit 1; }
    rm -rf ncurses ncursesw
    mkdir ncurses ncursesw
    ln -sf ../{curses.h,eti.h,form.h,menu.h,ncurses_dll.h,ncurses.h,panel.h,termcap.h,term_entry.h,term.h,unctrl.h} ncurses
    ln -sf ../{curses.h,eti.h,form.h,menu.h,ncurses_dll.h,ncurses.h,panel.h,termcap.h,term_entry.h,term.h,unctrl.h} ncursesw
}

termux_build_nano() {
    echo "Building nano..."
    cd "$TERMUX_TMPDIR/nano-$NANO_VERSION"
    export CFLAGS="-I$TERMUX_INCLUDE -L$TERMUX_LIB"
    ./configure $NANO_CONFIGURE_ARGS
    make -j$(nproc)
    make install DESTDIR="$TERMUX_PREFIX"
    rm -f "$TERMUX_BIN/rnano" "$TERMUX_ETC/man/man1/rnano.1"
    echo "include \"/system_ext/etc/nano/*nanorc\"" > "$TERMUX_ETC/nanorc"
    echo "export TERMINFO=/system_ext/etc/terminfo" >> "$TERMUX_ETC/profile"
}

main() {
    echo "Installing build dependencies..."
    pkg_install="pkg_install_$(uname -m)"
    $pkg_install build-essential wget tar patch xz-utils

    echo "Downloading sources..."
    termux_download "$LIBICONV_SRCURL" "$TERMUX_CACHEDIR/libiconv-$LIBICONV_VERSION.tar.gz"
    termux_download "$NCURSES_SRCURL" "$TERMUX_CACHEDIR/ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT.tar.gz"
    termux_download "$NANO_SRCURL" "$TERMUX_CACHEDIR/nano-$NANO_VERSION.tar.xz"

    termux_extract "$TERMUX_CACHEDIR/libiconv-$LIBICONV_VERSION.tar.gz" "libiconv-$LIBICONV_VERSION"
    termux_extract "$TERMUX_CACHEDIR/ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT.tar.gz" "ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT"
    tar -xf "$TERMUX_CACHEDIR/nano-$NANO_VERSION.tar.xz" -C "$TERMUX_TMPDIR"

    termux_build_libiconv
    termux_build_ncurses
    termux_build_nano

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
    pkg update -y && pkg install -y build-essential wget tar patch xz-utils binutils 
}

main
