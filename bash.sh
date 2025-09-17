#!/bin/bash

set -e

TERMUX_HOME="/data/data/com.termux/files/home"
TERMUX_PREFIX="${TERMUX_HOME}/system"
TERMUX_BIN="${TERMUX_PREFIX}/bin"
TERMUX_LIB="${TERMUX_PREFIX}/lib64"
TERMUX_SHARE="${TERMUX_PREFIX}/usr/share"
TERMUX_INCLUDE="${TERMUX_PREFIX}/include"
TERMUX_TMPDIR="${TERMUX_HOME}/tmp"
TERMUX_CACHEDIR="${TERMUX_HOME}/cache"

mkdir -p "$TERMUX_TMPDIR" "$TERMUX_CACHEDIR" "$TERMUX_BIN" "$TERMUX_LIB" "$TERMUX_LIB/pkgconfig" "$TERMUX_SHARE" "$TERMUX_INCLUDE" "$TERMUX_SHARE/terminfo" "$TERMUX_PREFIX/etc"

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
LIBICONV_CONFIGURE_ARGS="--enable-extra-encodings --prefix=$TERMUX_PREFIX --includedir=$TERMUX_INCLUDE --libdir=$TERMUX_LIB"

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
--mandir=$TERMUX_SHARE/man
--includedir=$TERMUX_INCLUDE
--with-pkg-config-libdir=$TERMUX_LIB/pkgconfig
--with-static
--with-shared
--with-termpath=$TERMUX_PREFIX/etc/termcap:$TERMUX_SHARE/misc/termcap
--prefix=$TERMUX_PREFIX
"

READLINE_MAIN_VERSION="8.3"
READLINE_PATCH_VERSION="1"
READLINE_VERSION="$READLINE_MAIN_VERSION.$READLINE_PATCH_VERSION"
READLINE_SRCURL="https://mirrors.kernel.org/gnu/readline/readline-$READLINE_MAIN_VERSION.tar.gz"
READLINE_PATCH_URL="http://mirrors.kernel.org/gnu/readline/readline-$READLINE_MAIN_VERSION-patches/readline${READLINE_MAIN_VERSION/./}-001"
READLINE_CONFIGURE_ARGS="--with-curses --enable-multibyte bash_cv_wcwidth_broken=no --prefix=$TERMUX_PREFIX --includedir=$TERMUX_INCLUDE --libdir=$TERMUX_LIB"
READLINE_MAKE_ARGS="SHLIB_LIBS=-lncursesw"

BASH_MAIN_VERSION="5.3"
BASH_PATCH_VERSION="3"
BASH_VERSION="$BASH_MAIN_VERSION.$BASH_PATCH_VERSION"
BASH_SRCURL="https://mirrors.kernel.org/gnu/bash/bash-$BASH_MAIN_VERSION.tar.gz"
BASH_PATCH_URLS=(
    "https://mirrors.kernel.org/gnu/bash/bash-$BASH_MAIN_VERSION-patches/bash${BASH_MAIN_VERSION/./}-001"
    "https://mirrors.kernel.org/gnu/bash/bash-$BASH_MAIN_VERSION-patches/bash${BASH_MAIN_VERSION/./}-002"
    "https://mirrors.kernel.org/gnu/bash/bash-$BASH_MAIN_VERSION-patches/bash${BASH_MAIN_VERSION/./}-003"
)
BASH_CONFIGURE_ARGS="
--enable-multibyte
--without-bash-malloc
--with-installed-readline
--enable-progcomp
bash_cv_job_control_missing=present
bash_cv_sys_siglist=yes
bash_cv_func_sigsetjmp=present
bash_cv_unusable_rtsigs=no
ac_cv_func_mbsnrtowcs=no
bash_cv_dev_fd=whacky
bash_cv_getcwd_malloc=yes
--prefix=$TERMUX_PREFIX
--includedir=$TERMUX_INCLUDE
--libdir=$TERMUX_LIB
"

termux_build_libiconv() {
    echo "Building libiconv..."
    cd "$TERMUX_TMPDIR/libiconv-$LIBICONV_VERSION"
    ./configure $LIBICONV_CONFIGURE_ARGS
    make -j$(nproc)
    make install
}

termux_build_ncurses() {
    echo "Building ncurses..."
    cd "$TERMUX_TMPDIR/ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT"
    export CPPFLAGS="-fPIC"
    ./configure $NCURSES_CONFIGURE_ARGS
    make -j$(nproc)
    make install

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

    local TI="$TERMUX_SHARE/terminfo"
    mkdir -p "$TI"/{a,d,e,f,g,n,k,l,p,r,s,t,v,x}
    cp -r "$TERMUX_PREFIX"/share/terminfo/a/{alacritty{,+common,-direct},ansi} "$TI/a/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/d/{dtterm,dumb} "$TI/d/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/e/eterm-color "$TI/e/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/f/foot{,+base,-direct} "$TI/f/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/g/gnome{,-256color} "$TI/g/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/n/nsterm "$TI/n/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/k/kitty{,+common,-direct} "$TI/k/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/l/linux "$TI/l/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/p/putty{,-256color} "$TI/p/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/r/rxvt{,-256color} "$TI/r/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/s/{screen{,2,-256color},st{,-256color}} "$TI/s/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/t/tmux{,-256color} "$TI/t/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/v/vt{52,100,102} "$TI/v/" || true
    cp -r "$TERMUX_PREFIX"/share/terminfo/x/xterm{,-color,-new,-16color,-256color,+256color} "$TI/x/" || true
}

termux_build_readline() {
    echo "Building readline..."
    cd "$TERMUX_TMPDIR/readline-$READLINE_MAIN_VERSION"
    if [ "$READLINE_PATCH_VERSION" != "0" ]; then
        local PATCHFILE="$TERMUX_CACHEDIR/readline_patch_001.patch"
        termux_download "$READLINE_PATCH_URL" "$PATCHFILE"
        patch -p0 -i "$PATCHFILE"
    fi
    export CFLAGS="-fexceptions -I$TERMUX_INCLUDE -L$TERMUX_LIB"
    ./configure $READLINE_CONFIGURE_ARGS
    make -j$(nproc) $READLINE_MAKE_ARGS
    make install
    cp readline.pc "$TERMUX_LIB/pkgconfig/"
    echo -e "set editing-mode vi\nset keymap vi" > "$TERMUX_PREFIX/etc/inputrc"
}

termux_build_bash() {
    echo "Building bash..."
    cd "$TERMUX_TMPDIR/bash-$BASH_MAIN_VERSION"
    if [ "$BASH_PATCH_VERSION" != "0" ]; then
        for PATCH_NUM in $(seq -f '%03g' $BASH_PATCH_VERSION); do
            local PATCHFILE="$TERMUX_CACHEDIR/bash_patch_${PATCH_NUM}.patch"
            termux_download "${BASH_PATCH_URLS[$((PATCH_NUM-1))]}" "$PATCHFILE"
            patch -p0 -i "$PATCHFILE"
        done
    fi
    export CFLAGS="-I$TERMUX_INCLUDE -L$TERMUX_LIB"
    ./configure $BASH_CONFIGURE_ARGS
    make -j$(nproc)
    make install
    echo -e "export PATH=$TERMUX_PREFIX/bin:\$PATH" > "$TERMUX_PREFIX/etc/profile"
    echo -e "if [ -f $TERMUX_PREFIX/etc/bash.bashrc ]; then\n    . $TERMUX_PREFIX/etc/bash.bashrc\nfi" >> "$TERMUX_PREFIX/etc/profile"
    echo -e "[ -z \"\$PS1\" ] && return\nshopt -s histappend\nHISTCONTROL=ignoreboth\nHISTSIZE=1000\nHISTFILESIZE=2000\nshopt -s checkwinsize" > "$TERMUX_PREFIX/etc/bash.bashrc"
}

main() {
    echo "Installing build dependencies..."
    pkg_install="pkg_install_$(uname -m)"
    $pkg_install build-essential wget tar patch

    echo "Downloading sources..."
    termux_download "$LIBICONV_SRCURL" "$TERMUX_CACHEDIR/libiconv-$LIBICONV_VERSION.tar.gz"
    termux_download "$NCURSES_SRCURL" "$TERMUX_CACHEDIR/ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT.tar.gz"
    termux_download "$READLINE_SRCURL" "$TERMUX_CACHEDIR/readline-$READLINE_MAIN_VERSION.tar.gz"
    termux_download "$BASH_SRCURL" "$TERMUX_CACHEDIR/bash-$BASH_MAIN_VERSION.tar.gz"

    termux_extract "$TERMUX_CACHEDIR/libiconv-$LIBICONV_VERSION.tar.gz" "libiconv-$LIBICONV_VERSION"
    termux_extract "$TERMUX_CACHEDIR/ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT.tar.gz" "ncurses-snapshots-$NCURSES_SNAPSHOT_COMMIT"
    termux_extract "$TERMUX_CACHEDIR/readline-$READLINE_MAIN_VERSION.tar.gz" "readline-$READLINE_MAIN_VERSION"
    termux_extract "$TERMUX_CACHEDIR/bash-$BASH_MAIN_VERSION.tar.gz" "bash-$BASH_MAIN_VERSION"

    termux_build_libiconv
    termux_build_ncurses
    termux_build_readline
    termux_build_bash

    echo "- Binaries: $TERMUX_BIN"
    echo "- Libraries: $TERMUX_LIB"
    echo "- Headers: $TERMUX_INCLUDE"
    echo "- Share: $TERMUX_SHARE"
}

pkg_install_aarch64() {
    pkg_install_arm64
}
pkg_install_arm64() {
    pkg update -y && pkg install -y build-essential wget tar patch binutils 
}
pkg_install_arm() {
    pkg update -y && pkg install -y build-essential wget tar patch binutils 
}
pkg_install_x86_64() {
    pkg update -y && pkg install -y build-essential wget tar patch binutils 
}

main
