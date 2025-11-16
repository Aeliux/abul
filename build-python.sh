#!/usr/bin/env bash
set -euo pipefail
shopt -s extglob

# -----------------------
# CONFIGURATION
# -----------------------
TERMUX_PREFIX=/data/data/com.termux/files/usr
PYVER="3.13.9"
ZLIB_VER="1.3.1"
LIBFFI_VER="3.5.2"
OPENSSL_VER="3.5.4"
XZ_VER="5.8.1"
NCURSES_VER="6.5"
READLINE_VER="8.3"
BZIP2_VER="1.0.8"
GDBM_VER="1.26"

NDK_VER="r27d"
NDK_DOWNLOAD_URL="https://dl.google.com/android/repository/android-ndk-${NDK_VER}-linux.tar.xz"

ANDROID_API=34
TARGET_TRIPLE="aarch64-linux-android"
HOST_TAG="linux-x86_64"
BUILD_THREADS=$(nproc)

# Workspace layout
WORKDIR="${HOME}/workspace/python${PYVER}"
DOWNLOADS_DIR="${WORKDIR}/downloads"
SRC_DIR="${WORKDIR}/src"
STAGING_DIR="${WORKDIR}/artifacts"
OUTPUT_DIR="${WORKDIR}/out"
HOST_PY_PREFIX="${WORKDIR}/host-python"  # install location for host/python used during cross build

# NDK target location when extracted
NDK_DIR="${WORKDIR}/ndk/android-ndk-${NDK_VER}"

# Convenience: editing rarely needed below this line
LOGFILE="${WORKDIR}/build.log"
mkdir -p "$WORKDIR" "$DOWNLOADS_DIR" "$SRC_DIR" "$STAGING_DIR" "$OUTPUT_DIR"

# directory to store build markers
BUILT_MARK_DIR="${STAGING_DIR}/.built"
mkdir -p "$BUILT_MARK_DIR"

# create safe atomic marker
mark_built() {
  # args: component_name marker_content
  local name="$1"; shift
  local content="$*"
  local tmp
  tmp="$(mktemp "${BUILT_MARK_DIR}/${name}.tmp.XXXX")"
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "${BUILT_MARK_DIR}/${name}"
  log "Marked built: ${name}"
}

# check if a plain marker exists
is_built_plain() {
  # args: component_name
  [ -f "${BUILT_MARK_DIR}/$1" ]
}

# check if marker exists and content matches
is_built_match() {
  # args: component_name expected_content
  local name="$1"; shift
  local expected="$*"
  local file="${BUILT_MARK_DIR}/${name}"
  if [ ! -f "$file" ]; then return 1; fi
  # compare content exactly
  if [ "$(cat "$file")" = "$expected" ]; then
    return 0
  fi
  return 1
}

# compute sha256 of a file (portable)
sha256_of() {
  # arg: path
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    # fallback for systems without sha256sum
    openssl dgst -sha256 "$1" | awk '{print $2}'
  fi
}

# -----------------------
# helper functions
# -----------------------
log() { printf '%s %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOGFILE"; }
fatal() { echo "ERROR: $*" | tee -a "$LOGFILE" >&2; exit 1; }

check_host_deps() {
  # minimal list of packages required on Ubuntu 24
  local req=(build-essential clang llvm cmake git wget unzip pkg-config automake autoconf libtool bison \
             libbz2-dev libsqlite3-dev libreadline-dev libncurses-dev libffi-dev liblzma-dev \
             zlib1g-dev libssl-dev perl python3 texinfo autopoint po4a)
  local missing=()
  for p in "${req[@]}"; do
    if ! dpkg -s "$p" >/dev/null 2>&1; then
      missing+=("$p")
    fi
  done
  if [ ${#missing[@]} -ne 0 ]; then
    echo
    echo "Missing host packages (install on Ubuntu 24):"
    printf '  %s\n' "${missing[@]}"
    echo
    echo "Install with:"
    echo "  sudo apt update && sudo apt install -y ${missing[*]}"
    fatal "Install the packages above and re-run."
  fi
  log "Host dependencies OK"
}

fetch_if_missing() {
  local url="$1"; local out="$2"
  if [ -f "$out" ]; then
    log "Found download: $(basename "$out") — skipping"
    return 0
  fi
  log "Downloading: $url -> $out"
  wget -c -O "$out" "$url"
}

extract_if_missing() {
  local archive="$1"; local dest="$2"
  if [ -d "$dest" ]; then
    log "Source dir exists: $dest — skipping extract"
    return 0
  fi

  local parent
  parent="$(dirname "$dest")"
  mkdir -p "$parent"

  log "Extracting $archive -> $parent"
  case "$archive" in
    *.tar.xz) tar -xJf "$archive" -C "$parent" ;;
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$parent" ;;
    *.zip) unzip -q "$archive" -d "$parent" && return 0 ;;
    *) fatal "Unknown archive format: $archive" ;;
  esac

  # Normalize: if the archive created a top-level dir (common), move it to $dest
  local top
  top="$(tar -tf "$archive" | head -1 | cut -f1 -d/ || true)"
  if [ -n "$top" ] && [ -d "${parent}/${top}" ] && [ "${parent}/${top}" != "$dest" ]; then
    log "Moving ${parent}/${top} -> $dest"
    mv "${parent}/${top}" "$dest"
  fi
}


ensure_ndk() {
  if [ -n "${ANDROID_NDK_ROOT:-}" ] && [ -d "${ANDROID_NDK_ROOT}" ]; then
    log "Using ANDROID_NDK_ROOT=${ANDROID_NDK_ROOT}"
    return 0
  fi
  if [ -d "$NDK_DIR" ]; then
    export ANDROID_NDK_ROOT="$NDK_DIR"
    log "Found NDK at $ANDROID_NDK_ROOT"
    return 0
  fi
  if [ -n "$NDK_DOWNLOAD_URL" ]; then
    local filename="$DOWNLOADS_DIR/$(basename "$NDK_DOWNLOAD_URL")"
    fetch_if_missing "$NDK_DOWNLOAD_URL" "$filename"
    log "Extracting NDK archive"
    mkdir -p "$(dirname "$NDK_DIR")"
    tar -xJf "$filename" -C "$(dirname "$NDK_DIR")"
    if [ -d "$NDK_DIR" ]; then
      export ANDROID_NDK_ROOT="$NDK_DIR"
      log "NDK extracted to $ANDROID_NDK_ROOT"
      return 0
    else
      fatal "NDK extraction failed: expected $NDK_DIR to exist"
    fi
  fi
  cat <<EOF

NDK not found. Please either:
  * set ANDROID_NDK_ROOT to your extracted NDK path, or
  * set NDK_DOWNLOAD_URL at top of script to a valid NDK tar.xz URL so the script can download it.

Expected NDK path when downloaded: $NDK_DIR

EOF
  fatal "NDK missing"
}

clean_builddir() {
  # remove any per-component build dir to ensure a fresh start
  local d="$1"
  if [ -d "$d" ]; then
    log "Cleaning build dir: $d"
    rm -rf "$d"
  fi
}

# -----------------------
# prepare environment vars for toolchain
# -----------------------
prepare_toolchain_env() {
  TOOLCHAIN="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${HOST_TAG}"
  if [ ! -d "$TOOLCHAIN" ]; then
    fatal "Toolchain not found at $TOOLCHAIN (check NDK/host tag)"
  fi
  export API="$ANDROID_API"
  export TARGET_TRIPLE="$TARGET_TRIPLE"
  export CC="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API}-clang"
  export CXX="${TOOLCHAIN}/bin/${TARGET_TRIPLE}${API}-clang++"
  export AR="${TOOLCHAIN}/bin/llvm-ar"
  export RANLIB="${TOOLCHAIN}/bin/llvm-ranlib"
  export STRIP="${TOOLCHAIN}/bin/llvm-strip"
  export SYSROOT="${TOOLCHAIN}/sysroot"
  export CFLAGS="--sysroot=${SYSROOT} -fPIC"
  export CPPFLAGS="-I${STAGING_DIR}/include"
  export LDFLAGS="--sysroot=${SYSROOT} -L${STAGING_DIR}/lib"
  export PKG_CONFIG_LIBDIR="${STAGING_DIR}/lib/pkgconfig:${STAGING_DIR}/share/pkgconfig"
  export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}:${PKG_CONFIG_PATH:-}"
  log "Toolchain env prepared (CC=${CC})"
}

# -----------------------
# download sources
# -----------------------
prepare_sources() {
  log "Preparing downloads in $DOWNLOADS_DIR"
  fetch_if_missing "https://www.python.org/ftp/python/${PYVER}/Python-${PYVER}.tar.xz" "${DOWNLOADS_DIR}/Python-${PYVER}.tar.xz"
  fetch_if_missing "https://zlib.net/zlib-${ZLIB_VER}.tar.xz" "${DOWNLOADS_DIR}/zlib-${ZLIB_VER}.tar.xz"
  fetch_if_missing "https://github.com/libffi/libffi/archive/refs/tags/v${LIBFFI_VER}.tar.gz" "${DOWNLOADS_DIR}/libffi-${LIBFFI_VER}.tar.gz"
  fetch_if_missing "https://www.openssl.org/source/openssl-${OPENSSL_VER}.tar.gz" "${DOWNLOADS_DIR}/openssl-${OPENSSL_VER}.tar.gz"
  fetch_if_missing "https://github.com/tukaani-project/xz/archive/refs/tags/v${XZ_VER}.tar.gz" "${DOWNLOADS_DIR}/xz-${XZ_VER}.tar.gz"
  fetch_if_missing "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${NCURSES_VER}.tar.gz" "${DOWNLOADS_DIR}/ncurses-${NCURSES_VER}.tar.gz"
  fetch_if_missing "https://ftp.gnu.org/gnu/readline/readline-${READLINE_VER}.tar.gz" "${DOWNLOADS_DIR}/readline-${READLINE_VER}.tar.gz"
  fetch_if_missing "https://sqlite.org/2025/sqlite-src-3510000.zip" "${DOWNLOADS_DIR}/sqlite-src-3510000.zip"
  fetch_if_missing "https://sourceware.org/pub/bzip2/bzip2-${BZIP2_VER}.tar.gz" "${DOWNLOADS_DIR}/bzip2-${BZIP2_VER}.tar.gz"
  fetch_if_missing "https://ftp.gnu.org/gnu/gdbm/gdbm-${GDBM_VER}.tar.gz" "${DOWNLOADS_DIR}/gdbm-${GDBM_VER}.tar.gz"
  log "Downloads ready"
}

# -----------------------
# build host python (native)
# -----------------------
build_host_python() {
  local comp="python-host-${PYVER}"
  local archive="${DOWNLOADS_DIR}/Python-${PYVER}.tar.xz"
  local srcdir="${SRC_DIR}/Python-${PYVER}-host"
  local marker_name="${comp}.stamp"

  # marker content: archive sha + uname + some configure flags (keeps it conservative)
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content
  marker_content="archive=${archive_hash};uname=$(uname -a);configure=--enable-shared"

  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date"
    export HOSTPYTHON="${HOST_PY_PREFIX}/bin/python3"
    return 0
  fi

  clean_builddir "$srcdir"
  extract_if_missing "${archive}" "$srcdir"
  pushd "$srcdir" >/dev/null

  log "Configuring host Python in $srcdir"
  LDFLAGS="-Wl,-rpath=${HOST_PY_PREFIX}/lib" ./configure --prefix="$HOST_PY_PREFIX" --enable-shared --enable-optimizations
  make -j"$BUILD_THREADS"
  make install

  popd >/dev/null

  # sanity check
  if [ ! -x "${HOST_PY_PREFIX}/bin/python3" ]; then
    fatal "Host python not installed at ${HOST_PY_PREFIX}/bin/python3"
  fi
  export HOSTPYTHON="${HOST_PY_PREFIX}/bin/python3"

  mark_built "$marker_name" "$marker_content"
  log "Built host python: $HOSTPYTHON"
}

# -----------------------
# build zlib for target
# -----------------------
build_zlib() {
  local comp="zlib-${ZLIB_VER}"
  local archive="${DOWNLOADS_DIR}/zlib-${ZLIB_VER}.tar.xz"
  local marker_name="${comp}.stamp"

  # compute marker content: archive sha + relevant CFLAGS
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"

  # skip if marker matches (no rebuild)
  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date marker present"
    return 0
  fi

  # clean/build dir
  local BUILD_DIR="${SRC_DIR}/zlib-${ZLIB_VER}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # build using cross toolchain
  env CC="$CC" CFLAGS="$CFLAGS" ./configure --prefix="$STAGING_DIR" --static
  make -j"$BUILD_THREADS"
  make install
  popd >/dev/null

  # if we reached here, build succeeded -> mark built
  mark_built "$marker_name" "$marker_content"
  log "${comp} built and staged"
}

# -----------------------
# build libffi for target (simple autotools approach)
# -----------------------
build_libffi() {
  local comp="libffi-${LIBFFI_VER}"
  local archive="${DOWNLOADS_DIR}/libffi-${LIBFFI_VER}.tar.gz"
  local marker_name="${comp}.stamp"

  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};target=${TARGET_TRIPLE};cflags=${CFLAGS}"

  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date"
    return 0
  fi

  local BUILD_DIR="${SRC_DIR}/libffi-${LIBFFI_VER}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # Ensure configure exists (some releases require autogen)
  if [ ! -x "./configure" ]; then
    if [ -x "./autogen.sh" ]; then
      ./autogen.sh
    else
      log "No configure/autogen; attempting autoreconf"
      autoreconf -fi || true
    fi
  fi

  log "Configuring libffi for host=${TARGET_TRIPLE}"
  CC="$CC" CFLAGS="$CFLAGS" ./configure --host="$TARGET_TRIPLE" --prefix="$STAGING_DIR" --disable-shared
  make -j"$BUILD_THREADS"
  make install

  popd >/dev/null

  mark_built "$marker_name" "$marker_content"
  log "libffi built and staged to $STAGING_DIR"
}

# -----------------------
# build openssl for android
# -----------------------
build_openssl() {
  local comp="openssl-${OPENSSL_VER}"
  local archive="${DOWNLOADS_DIR}/openssl-${OPENSSL_VER}.tar.gz"
  local marker_name="${comp}.stamp"

  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};api=${API};cc=$(basename "$CC")"

  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date"
    return 0
  fi

  local BUILD_DIR="${SRC_DIR}/openssl-${OPENSSL_VER}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  log "Configuring OpenSSL (android-arm64)"
  # Use perl Configure for Android target
  PATH=$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/linux-x86_64/bin:$ANDROID_NDK_ROOT/toolchains/arm-linux-androideabi-4.9/prebuilt/linux-x86_64/bin:$PATH
  perl Configure android-arm64 --prefix="$STAGING_DIR" no-shared --openssldir="$STAGING_DIR/ssl"
  make CC="$CC" -j"$BUILD_THREADS"
  make install_sw

  popd >/dev/null

  mark_built "$marker_name" "$marker_content"
  log "OpenSSL built and staged to $STAGING_DIR"
}

# -----------------------
# build xz for target
# -----------------------
build_xz() {
  local comp="xz-${XZ_VER}"
  local archive="${DOWNLOADS_DIR}/xz-${XZ_VER}.tar.gz"
  local marker_name="${comp}.stamp"

  # compute marker content: archive sha + relevant CFLAGS
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"

  # skip if marker matches (no rebuild)
  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date marker present"
    return 0
  fi

  local BUILD_DIR="${SRC_DIR}/xz-${XZ_VER}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  if [ ! -x "./configure" ]; then
    if [ -x "./autogen.sh" ]; then
      ./autogen.sh
    else
      log "No configure/autogen; attempting autoreconf"
      autoreconf -fi || true
    fi
  fi

  # build using cross toolchain
  CC="$CC" CFLAGS="$CFLAGS" ./configure --host="$TARGET_TRIPLE" --prefix="$STAGING_DIR" --disable-shared SKIP_WERROR_CHECK=yes
  make -j"$BUILD_THREADS"
  make install
  popd >/dev/null

  # if we reached here, build succeeded -> mark built
  mark_built "$marker_name" "$marker_content"
  log "${comp} built and staged"
}

# -----------------------
# build ncurses for target
# -----------------------
build_ncurses() {
  local comp="ncurses-${ZLIB_VER}"
  local archive="${DOWNLOADS_DIR}/ncurses-${NCURSES_VER}.tar.gz"
  local marker_name="${comp}.stamp"

  # compute marker content: archive sha + relevant CFLAGS
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"

  # skip if marker matches (no rebuild)
  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date marker present"
    return 0
  fi

  # clean/build dir
  local BUILD_DIR="${SRC_DIR}/ncurses-${NCURSES_VER}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # build using cross toolchain
  CC="$CC" CFLAGS="$CFLAGS -O2" ./configure \
            --host="$TARGET_TRIPLE" \
            --prefix="$STAGING_DIR" \
            --with-shared \
            --enable-widec \
            --with-termlib \
            --with-terminfo-dirs="$TERMUX_PREFIX/share/terminfo" \
            --without-tests \
            --without-manpages \
            --without-progs \
            --without-debug
  make -j"$BUILD_THREADS"
  make install
  popd >/dev/null

  # if we reached here, build succeeded -> mark built
  mark_built "$marker_name" "$marker_content"
  log "${comp} built and staged"
}

# -----------------------
# build readline for target
# -----------------------
build_readline() {
  local comp="readline-${READLINE_VER}"
  local archive="${DOWNLOADS_DIR}/${comp}.tar.gz"
  local marker_name="${comp}.stamp"

  # compute marker content: archive sha + relevant CFLAGS
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"

  # skip if marker matches (no rebuild)
  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date marker present"
    return 0
  fi

  # clean/build dir
  local BUILD_DIR="${SRC_DIR}/${comp}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # build using cross toolchain
  CC="$CC" CFLAGS="$CFLAGS" ./configure --host="$TARGET_TRIPLE" --prefix="$STAGING_DIR" --disable-shared
  make -j"$BUILD_THREADS"
  make install
  popd >/dev/null

  # if we reached here, build succeeded -> mark built
  mark_built "$marker_name" "$marker_content"
  log "${comp} built and staged"
}

# -----------------------
# build sqlite for target
# -----------------------
build_sqlite() {
  local comp="sqlite-3.51.0"
  local archive="${DOWNLOADS_DIR}/sqlite-src-3510000.zip"
  local marker_name="${comp}.stamp"

  # compute marker content: archive sha + relevant CFLAGS
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"

  # skip if marker matches (no rebuild)
  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date marker present"
    return 0
  fi

  local BUILD_DIR="${SRC_DIR}/sqlite-src-3510000"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # build using cross toolchain
  CC="$CC" CFLAGS="$CFLAGS" ./configure --host="$TARGET_TRIPLE" --prefix="$STAGING_DIR" --enable-all
  make -j"$BUILD_THREADS"
  make install
  popd >/dev/null

  # if we reached here, build succeeded -> mark built
  mark_built "$marker_name" "$marker_content"
  log "${comp} built and staged"
}

# -----------------------
# build bzip2 for target
# -----------------------
build_bzip2() {
  local comp="bzip2-${BZIP2_VER}"
  local archive="${DOWNLOADS_DIR}/${comp}.tar.gz"
  local marker_name="${comp}.stamp"

  # compute marker content: archive sha + relevant CFLAGS
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"

  # skip if marker matches (no rebuild)
  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date marker present"
    return 0
  fi

  # clean/build dir
  local BUILD_DIR="${SRC_DIR}/${comp}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # build using cross toolchain
  make -j"$BUILD_THREADS" CC="$CC" CFLAGS="$CFLAGS" AR="$AR" RANLIB="$RANLIB" PREFIX="$STAGING_DIR" libbz2.a bzip2 bzip2recover
  make PREFIX="$STAGING_DIR" install
  popd >/dev/null

  # if we reached here, build succeeded -> mark built
  mark_built "$marker_name" "$marker_content"
  log "${comp} built and staged"
}

# -----------------------
# build gdbm for target
# -----------------------
build_gdbm() {
  local comp="gdbm-${GDBM_VER}"
  local archive="${DOWNLOADS_DIR}/${comp}.tar.gz"
  local marker_name="${comp}.stamp"

  # compute marker content: archive sha + relevant CFLAGS
  local archive_hash
  archive_hash="$(sha256_of "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"

  # skip if marker matches (no rebuild)
  if is_built_match "$marker_name" "$marker_content"; then
    log "Skipping ${comp}: up-to-date marker present"
    return 0
  fi

  # clean/build dir
  local BUILD_DIR="${SRC_DIR}/${comp}"
  clean_builddir "$BUILD_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # build using cross toolchain
  CC="$CC" CFLAGS="$CFLAGS" ./configure --host="$TARGET_TRIPLE" --prefix="$STAGING_DIR" --enable-libgdbm-compat
  make -j"$BUILD_THREADS"
  make install
  popd >/dev/null

  # if we reached here, build succeeded -> mark built
  mark_built "$marker_name" "$marker_content"
  log "${comp} built and staged"
}

# -----------------------
# build cross Python
# -----------------------
build_cross_python() {
  local archive="${DOWNLOADS_DIR}/Python-${PYVER}.tar.xz"

  if [ -z "${HOSTPYTHON:-}" ] || [ ! -x "$HOSTPYTHON" ]; then
    fatal "HOSTPYTHON not set or not executable; build_host_python must run first"
  fi

  local BUILD_DIR="${SRC_DIR}/Python-${PYVER}"
  clean_builddir "$BUILD_DIR"
  clean_builddir "$OUTPUT_DIR"
  extract_if_missing "${archive}" "$BUILD_DIR"
  pushd "$BUILD_DIR" >/dev/null

  # If hostpgen exists from the host-source tree, point HOSTPGEN to it (helps some builds)
  if [ -x "${SRC_DIR}/Python-${PYVER}-host/Parser/hostpgen" ]; then
    HOSTPGEN="${SRC_DIR}/Python-${PYVER}-host/Parser/hostpgen"
    log "Using HOSTPGEN=${HOSTPGEN}"
  fi

  # prepare environment for configure
  export CPPFLAGS="-I${STAGING_DIR}/include -I${STAGING_DIR}/include/ncursesw"
  
  export CFLAGS="${CFLAGS} ${CPPFLAGS} -O3 -march=armv8-a -fomit-frame-pointer -ffunction-sections -fdata-sections -fvisibility=hidden -fno-exceptions -fno-rtti -g0 -fPIC"
  export LDFLAGS="--sysroot=${SYSROOT} -Wl,-Bstatic -ltinfow -Wl,-Bdynamic -L${STAGING_DIR}/lib -Wl,-rpath=/data/data/com.termux/files/usr/lib -Wl,-O1 -Wl,--gc-sections -Wl,-z,relro -Wl,-z,now -Wl,-s -flto"
  
  log "Configuring cross Python for host=${TARGET_TRIPLE}"
  ./configure --host="${TARGET_TRIPLE}" --build="$(uname -m)-linux-gnu" \
      --prefix="$OUTPUT_DIR" \
      --with-build-python="$HOSTPYTHON" \
      --enable-shared \
      --with-ensurepip=install \
      --disable-test-modules \
      --with-openssl="$STAGING_DIR" \
      CC="$CC" AR="$AR" RANLIB="$RANLIB" STRIP="$STRIP" HOSTPYTHON="$HOSTPYTHON" HOSTPGEN="${HOSTPGEN:-}" \
      CPPFLAGS="$CPPFLAGS" CFLAGS="$CFLAGS" LDFLAGS="$LDFLAGS"

  make HOSTPYTHON="$HOSTPYTHON" -j"$BUILD_THREADS"
  make install

  popd >/dev/null

  # rm "$OUTPUT_DIR/bin/python3"
  # rm "$OUTPUT_DIR/bin/idle3"
  # rm "$OUTPUT_DIR/bin/python3-config"
  # rm "$OUTPUT_DIR/bin/pydoc3"

  log "Cross python built"
}

# -----------------------
# main flow
# -----------------------
main() {
  log "START build: PY=${PYVER} TARGET=${TARGET_TRIPLE} API=${ANDROID_API} WORKDIR=${WORKDIR}"

  check_host_deps
  prepare_sources

  build_host_python

  ensure_ndk
  prepare_toolchain_env

  # build dependencies (order matters)
  build_zlib
  build_bzip2
  build_libffi
  build_openssl
  build_xz
  build_ncurses
  build_readline
  build_gdbm
  build_sqlite

  # build Python for target
  build_cross_python

  log "Applying patches"

  # create envpatch
  mkdir -p "$OUTPUT_DIR/etc/profile.d"
  cat >> "$OUTPUT_DIR/etc/profile.d/python3.13-envpatch.sh" <<EOF
export PATH=\$PREFIX/bin:\$PATH
export CC=clang
export CXX=clang++
export LDSHARED="\$CC -shared"
export CPPFLAGS="-I\$PREFIX/include -I\$PREFIX/include/$TARGET_TRIPLE"
export LDFLAGS="-L\$PREFIX/lib"
export PKG_CONFIG_PATH="\$PREFIX/lib/pkgconfig:\$PKG_CONFIG_PATH"
# export TERMINFO=="\$PREFIX/share/terminfo
EOF

  # create tar.gz file
  local TAR_NAME="python-${PYVER}-${TARGET_TRIPLE}${ANDROID_API}.tar.gz"
  local TAR_PATH="$WORKDIR/$TAR_NAME"
  if [ -f "$TAR_PATH" ]; then
    rm "$TAR_PATH"
  fi
  cd "$OUTPUT_DIR"
  tar -czf "$TAR_PATH" .

  log "SUCCESS. Python runtime avaiable at: $OUTPUT_DIR"
  log "Archived file: $TAR_NAME"
}

main "$@"
