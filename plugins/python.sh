#!/usr/bin/env bash
# ABUL Plugin: Python
# Cross-compile Python for Android using NDK

# Constants
readonly TERMUX_PREFIX="/data/data/com.termux/files/usr"

# Plugin metadata
plugin::python::describe() {
  echo "Cross-compile Python for Android"
}

plugin::python::usage() {
  cat <<EOF
ABUL Python Plugin

Usage: abul python [OPTIONS] <version>

Arguments:
  version                Python version to build (e.g., 3.13.9)

Options:
  -h, --help             Show this help message
  --api LEVEL            Android API level (default: 34)
  --arch ARCH            Target architecture: aarch64, armv7a, x86_64, i686 (default: aarch64)
  --skip-host-python     Skip building host Python (use system Python)

Environment Variables:
  PYTHON_ZLIB_VERSION       zlib version (default: 1.3.1)
  PYTHON_LIBFFI_VERSION     libffi version (default: 3.5.2)
  PYTHON_OPENSSL_VERSION    OpenSSL version (default: 3.5.4)
  PYTHON_XZ_VERSION         xz version (default: 5.8.1)
  PYTHON_NCURSES_VERSION    ncurses version (default: 6.5)
  PYTHON_READLINE_VERSION   readline version (default: 8.3)
  PYTHON_BZIP2_VERSION      bzip2 version (default: 1.0.8)
  PYTHON_GDBM_VERSION       gdbm version (default: 1.26)

Examples:
  abul python 3.13.9
  abul python --api 34 --arch aarch64 3.13.9
  abul --env PYTHON_ZLIB_VERSION=1.3.1 python 3.13.9

EOF
}

# Plugin configuration
plugin::python::config() {
  # Python version (from arguments)
  PYTHON_VERSION="${1:-}"
  
  if [ -z "$PYTHON_VERSION" ]; then
    abul::log::error "Python version not specified"
    plugin::python::usage
    exit 1
  fi
  
  # Dependency versions (can be overridden via environment)
  PYTHON_ZLIB_VERSION="${PYTHON_ZLIB_VERSION:-1.3.1}"
  PYTHON_LIBFFI_VERSION="${PYTHON_LIBFFI_VERSION:-3.5.2}"
  PYTHON_OPENSSL_VERSION="${PYTHON_OPENSSL_VERSION:-3.5.4}"
  PYTHON_XZ_VERSION="${PYTHON_XZ_VERSION:-5.8.1}"
  PYTHON_NCURSES_VERSION="${PYTHON_NCURSES_VERSION:-6.5}"
  PYTHON_READLINE_VERSION="${PYTHON_READLINE_VERSION:-8.3}"
  PYTHON_BZIP2_VERSION="${PYTHON_BZIP2_VERSION:-1.0.8}"
  PYTHON_GDBM_VERSION="${PYTHON_GDBM_VERSION:-1.26}"
  PYTHON_SQLITE_VERSION="${PYTHON_SQLITE_VERSION:-3.51.0}"
  PYTHON_SQLITE_CODE="${PYTHON_SQLITE_CODE:-3510000}"
  
  # Host Python location
  PYTHON_HOST_PREFIX="${ABUL_PLUGIN_WORKSPACE}/host-python"
  
  abul::log::info "Python build configuration:"
  abul::log::info "  Version: ${PYTHON_VERSION}"
  abul::log::info "  Target: ${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}"
  abul::log::info "  Termux prefix: ${TERMUX_PREFIX}"
}

# Check host dependencies
plugin::python::check_deps() {
  local required_deps=(
    build-essential clang llvm cmake git wget unzip pkg-config
    automake autoconf libtool bison
    libbz2-dev libsqlite3-dev libreadline-dev libncurses-dev
    libffi-dev liblzma-dev zlib1g-dev libssl-dev
    perl python3 texinfo autopoint po4a
  )
  
  abul::env::check_host_deps "${required_deps[@]}"
}

# Download all required sources
plugin::python::download_sources() {
  abul::log::section "Downloading sources"
  
  abul::download::fetch \
    "https://www.python.org/ftp/python/${PYTHON_VERSION}/Python-${PYTHON_VERSION}.tar.xz" \
    "${ABUL_DOWNLOADS_DIR}/Python-${PYTHON_VERSION}.tar.xz" \
    "Python ${PYTHON_VERSION}"
  
  abul::download::fetch \
    "https://zlib.net/zlib-${PYTHON_ZLIB_VERSION}.tar.xz" \
    "${ABUL_DOWNLOADS_DIR}/zlib-${PYTHON_ZLIB_VERSION}.tar.xz" \
    "zlib ${PYTHON_ZLIB_VERSION}"
  
  abul::download::fetch \
    "https://github.com/libffi/libffi/archive/refs/tags/v${PYTHON_LIBFFI_VERSION}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/libffi-${PYTHON_LIBFFI_VERSION}.tar.gz" \
    "libffi ${PYTHON_LIBFFI_VERSION}"
  
  abul::download::fetch \
    "https://www.openssl.org/source/openssl-${PYTHON_OPENSSL_VERSION}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/openssl-${PYTHON_OPENSSL_VERSION}.tar.gz" \
    "OpenSSL ${PYTHON_OPENSSL_VERSION}"
  
  abul::download::fetch \
    "https://github.com/tukaani-project/xz/archive/refs/tags/v${PYTHON_XZ_VERSION}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/xz-${PYTHON_XZ_VERSION}.tar.gz" \
    "xz ${PYTHON_XZ_VERSION}"
  
  abul::download::fetch \
    "https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${PYTHON_NCURSES_VERSION}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/ncurses-${PYTHON_NCURSES_VERSION}.tar.gz" \
    "ncurses ${PYTHON_NCURSES_VERSION}"
  
  abul::download::fetch \
    "https://ftp.gnu.org/gnu/readline/readline-${PYTHON_READLINE_VERSION}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/readline-${PYTHON_READLINE_VERSION}.tar.gz" \
    "readline ${PYTHON_READLINE_VERSION}"
  
  abul::download::fetch \
    "https://sqlite.org/2025/sqlite-src-${PYTHON_SQLITE_CODE}.zip" \
    "${ABUL_DOWNLOADS_DIR}/sqlite-src-${PYTHON_SQLITE_CODE}.zip" \
    "SQLite ${PYTHON_SQLITE_VERSION}"
  
  abul::download::fetch \
    "https://sourceware.org/pub/bzip2/bzip2-${PYTHON_BZIP2_VERSION}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/bzip2-${PYTHON_BZIP2_VERSION}.tar.gz" \
    "bzip2 ${PYTHON_BZIP2_VERSION}"
  
  abul::download::fetch \
    "https://ftp.gnu.org/gnu/gdbm/gdbm-${PYTHON_GDBM_VERSION}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/gdbm-${PYTHON_GDBM_VERSION}.tar.gz" \
    "gdbm ${PYTHON_GDBM_VERSION}"
}

# Setup host Python (use system or build)
plugin::python::setup_host_python() {
  local skip_build="${1:-false}"
  
  # Extract major.minor version from PYTHON_VERSION (e.g., 3.13.9 -> 3.13)
  local py_major_minor
  py_major_minor="$(echo "$PYTHON_VERSION" | cut -d. -f1,2)"
  
  # Check if compatible Python exists in PATH
  if [ "$skip_build" = "true" ] || abul::common::command_exists "python${py_major_minor}"; then
    local system_python
    
    # Try python3.X first, then python3, then python
    if abul::common::command_exists "python${py_major_minor}"; then
      system_python="python${py_major_minor}"
    elif abul::common::command_exists python3; then
      system_python="python3"
    elif abul::common::command_exists python; then
      system_python="python"
    fi
    
    if [ -n "${system_python:-}" ]; then
      local sys_version
      sys_version="$("$system_python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "")"
      
      if [ "$sys_version" = "$py_major_minor" ]; then
        export HOSTPYTHON="$(command -v "$system_python")"
        abul::log::success "Using system Python: $HOSTPYTHON (${sys_version})"
        return 0
      else
        abul::log::warn "System Python version (${sys_version}) doesn't match target (${py_major_minor})"
      fi
    fi
  fi
  
  # Check if we already built it
  if [ -x "${PYTHON_HOST_PREFIX}/bin/python3" ]; then
    export HOSTPYTHON="${PYTHON_HOST_PREFIX}/bin/python3"
    abul::log::info "Using previously built host Python: $HOSTPYTHON"
    return 0
  fi
  
  # Build host Python
  local comp="python-host-${PYTHON_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/Python-${PYTHON_VERSION}.tar.xz"
  local src_dir="${ABUL_SRC_DIR}/Python-${PYTHON_VERSION}-host"
  
  local archive_hash
  archive_hash="$(abul::common::sha256 "$archive")"
  local marker_content="archive=${archive_hash};uname=$(uname -m)"
  
  if abul::plugin::is_built_match "$comp" "$marker_content"; then
    export HOSTPYTHON="${PYTHON_HOST_PREFIX}/bin/python3"
    abul::log::info "Host Python already built: $HOSTPYTHON"
    return 0
  fi
  
  abul::log::section "Building host Python ${PYTHON_VERSION}"
  
  abul::common::clean_builddir "$src_dir"
  abul::extract::archive "$archive" "$src_dir" "Python ${PYTHON_VERSION} (host)"
  
  pushd "$src_dir" >/dev/null
  
  abul::log::info "Configuring host Python..."
  LDFLAGS="-Wl,-rpath=${PYTHON_HOST_PREFIX}/lib" \
  ./configure \
    --prefix="$PYTHON_HOST_PREFIX" \
    --enable-shared \
    --enable-optimizations
  
  abul::log::info "Building host Python..."
  make -j"${ABUL_BUILD_THREADS}"
  
  abul::log::info "Installing host Python..."
  make install
  
  popd >/dev/null
  
  if [ ! -x "${PYTHON_HOST_PREFIX}/bin/python3" ]; then
    abul::log::fatal "Host Python installation failed"
  fi
  
  export HOSTPYTHON="${PYTHON_HOST_PREFIX}/bin/python3"
  abul::plugin::mark_built "$comp" "$marker_content"
  abul::log::success "Host Python built: $HOSTPYTHON"
}

# Build zlib (custom build due to non-standard configure)
plugin::python::build_zlib() {
  local comp="zlib-${PYTHON_ZLIB_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/zlib-${PYTHON_ZLIB_VERSION}.tar.xz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  local archive_hash
  archive_hash="$(abul::common::sha256 "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS}"
  
  if abul::plugin::is_built_match "$comp" "$marker_content"; then
    abul::log::info "Skipping ${comp}: already built"
    return 0
  fi
  
  abul::log::section "Building ${comp}"
  
  abul::common::clean_builddir "$src_dir"
  abul::extract::archive "$archive" "$src_dir" "$comp"
  
  pushd "$src_dir" >/dev/null
  
  abul::log::info "Configuring ${comp}..."
  CC="$CC" CFLAGS="$CFLAGS" ./configure --prefix="$ABUL_STAGING_DIR" --static
  
  abul::log::info "Building ${comp}..."
  make -j"${ABUL_BUILD_THREADS}"
  
  abul::log::info "Installing ${comp}..."
  make install
  
  popd >/dev/null
  
  abul::plugin::mark_built "$comp" "$marker_content"
  abul::log::success "${comp} built"
}

# Build libffi
plugin::python::build_libffi() {
  local comp="libffi-${PYTHON_LIBFFI_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/${comp}.tar.gz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  abul::plugin::build_component \
    "$comp" \
    "$archive" \
    "$src_dir" \
    abul::plugin::build_autotools \
    --disable-shared
}

# Build OpenSSL (custom build due to Configure script)
plugin::python::build_openssl() {
  local comp="openssl-${PYTHON_OPENSSL_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/${comp}.tar.gz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  local archive_hash
  archive_hash="$(abul::common::sha256 "$archive")"
  local marker_content="archive=${archive_hash};api=${ABUL_ANDROID_API};arch=${ABUL_TARGET_ARCH}"
  
  if abul::plugin::is_built_match "$comp" "$marker_content"; then
    abul::log::info "Skipping ${comp}: already built"
    return 0
  fi
  
  abul::log::section "Building ${comp}"
  
  abul::common::clean_builddir "$src_dir"
  abul::extract::archive "$archive" "$src_dir" "$comp"
  
  pushd "$src_dir" >/dev/null
  
  # Determine OpenSSL target based on architecture
  local openssl_target
  case "${ABUL_TARGET_ARCH}" in
    aarch64) openssl_target="android-arm64" ;;
    armv7a) openssl_target="android-arm" ;;
    x86_64) openssl_target="android-x86_64" ;;
    i686) openssl_target="android-x86" ;;
    *) abul::log::fatal "Unknown architecture for OpenSSL: ${ABUL_TARGET_ARCH}" ;;
  esac
  
  abul::log::info "Configuring ${comp} for ${openssl_target}..."
  PATH="${ABUL_TOOLCHAIN}/bin:$PATH" \
  perl Configure "$openssl_target" \
    --prefix="$ABUL_STAGING_DIR" \
    --openssldir="$ABUL_STAGING_DIR/ssl" \
    no-shared
  
  abul::log::info "Building ${comp}..."
  make CC="$CC" -j"${ABUL_BUILD_THREADS}"
  
  abul::log::info "Installing ${comp}..."
  make install_sw
  
  popd >/dev/null
  
  abul::plugin::mark_built "$comp" "$marker_content"
  abul::log::success "${comp} built"
}

# Build xz
plugin::python::build_xz() {
  local comp="xz-${PYTHON_XZ_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/${comp}.tar.gz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  abul::plugin::build_component \
    "$comp" \
    "$archive" \
    "$src_dir" \
    abul::plugin::build_autotools \
    --disable-shared \
    SKIP_WERROR_CHECK=yes
}

# Build ncurses
plugin::python::build_ncurses() {
  local comp="ncurses-${PYTHON_NCURSES_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/${comp}.tar.gz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  abul::plugin::build_component \
    "$comp" \
    "$archive" \
    "$src_dir" \
    abul::plugin::build_autotools \
    --with-shared \
    --enable-widec \
    --with-termlib \
    --with-terminfo-dirs="${TERMUX_PREFIX}/share/terminfo" \
    --without-tests \
    --without-manpages \
    --without-progs \
    --without-debug
}

# Build readline
plugin::python::build_readline() {
  local comp="readline-${PYTHON_READLINE_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/${comp}.tar.gz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  abul::plugin::build_component \
    "$comp" \
    "$archive" \
    "$src_dir" \
    abul::plugin::build_autotools \
    --disable-shared
}

# Build SQLite
plugin::python::build_sqlite() {
  local comp="sqlite-${PYTHON_SQLITE_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/sqlite-src-${PYTHON_SQLITE_CODE}.zip"
  local src_dir="${ABUL_SRC_DIR}/sqlite-src-${PYTHON_SQLITE_CODE}"
  
  abul::plugin::build_component \
    "$comp" \
    "$archive" \
    "$src_dir" \
    abul::plugin::build_autotools \
    --enable-all
}

# Build bzip2 (custom build - uses Makefile directly, no configure)
plugin::python::build_bzip2() {
  local comp="bzip2-${PYTHON_BZIP2_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/${comp}.tar.gz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  local archive_hash
  archive_hash="$(abul::common::sha256 "$archive")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS}"
  
  if abul::plugin::is_built_match "$comp" "$marker_content"; then
    abul::log::info "Skipping ${comp}: already built"
    return 0
  fi
  
  abul::log::section "Building ${comp}"
  
  abul::common::clean_builddir "$src_dir"
  abul::extract::archive "$archive" "$src_dir" "$comp"
  
  pushd "$src_dir" >/dev/null
  
  abul::log::info "Building ${comp}..."
  make -j"${ABUL_BUILD_THREADS}" \
    CC="$CC" \
    CFLAGS="$CFLAGS" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    PREFIX="$ABUL_STAGING_DIR" \
    libbz2.a bzip2 bzip2recover
  
  abul::log::info "Installing ${comp}..."
  make PREFIX="$ABUL_STAGING_DIR" install
  
  popd >/dev/null
  
  abul::plugin::mark_built "$comp" "$marker_content"
  abul::log::success "${comp} built"
}

# Build gdbm
plugin::python::build_gdbm() {
  local comp="gdbm-${PYTHON_GDBM_VERSION}"
  local archive="${ABUL_DOWNLOADS_DIR}/${comp}.tar.gz"
  local src_dir="${ABUL_SRC_DIR}/${comp}"
  
  abul::plugin::build_component \
    "$comp" \
    "$archive" \
    "$src_dir" \
    abul::plugin::build_autotools \
    --enable-libgdbm-compat
}

# Build cross-compiled Python
plugin::python::build_cross() {
  local archive="${ABUL_DOWNLOADS_DIR}/Python-${PYTHON_VERSION}.tar.xz"
  local src_dir="${ABUL_SRC_DIR}/Python-${PYTHON_VERSION}"
  
  if [ -z "${HOSTPYTHON:-}" ] || [ ! -x "$HOSTPYTHON" ]; then
    abul::log::fatal "HOSTPYTHON not set. Host Python must be built first."
  fi
  
  abul::log::section "Building cross-compiled Python ${PYTHON_VERSION}"
  
  abul::common::clean_builddir "$src_dir"
  abul::common::clean_builddir "$ABUL_OUTPUT_DIR"
  abul::extract::archive "$archive" "$src_dir" "Python ${PYTHON_VERSION}"
  
  pushd "$src_dir" >/dev/null
  
  # Enhanced build flags
  export CPPFLAGS="-I${ABUL_STAGING_DIR}/include -I${ABUL_STAGING_DIR}/include/ncursesw"
  
  # Architecture-specific optimization flags
  local arch_flags=""
  case "${ABUL_TARGET_ARCH}" in
    aarch64) arch_flags="-march=armv8-a" ;;
    armv7a) arch_flags="-march=armv7-a -mthumb" ;;
    x86_64) arch_flags="-march=x86-64" ;;
    i686) arch_flags="-march=i686" ;;
  esac
  
  export CFLAGS="--sysroot=${SYSROOT} -fPIC -O3 ${arch_flags} -fomit-frame-pointer -ffunction-sections -fdata-sections -fvisibility=hidden -g0"
  export LDFLAGS="--sysroot=${SYSROOT} -Wl,-Bstatic -ltinfow -Wl,-Bdynamic -L${ABUL_STAGING_DIR}/lib -Wl,-rpath=${TERMUX_PREFIX}/lib -Wl,-O1 -Wl,--gc-sections -Wl,-z,relro -Wl,-z,now -Wl,-s -flto"
  
  abul::log::info "Configuring Python for ${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}..."
  ./configure \
    --host="${ABUL_TARGET_TRIPLE}" \
    --build="$(uname -m)-linux-gnu" \
    --prefix="$ABUL_OUTPUT_DIR" \
    --with-build-python="$HOSTPYTHON" \
    --enable-shared \
    --with-ensurepip=install \
    --disable-test-modules \
    --with-openssl="$ABUL_STAGING_DIR" \
    CC="$CC" \
    AR="$AR" \
    RANLIB="$RANLIB" \
    STRIP="$STRIP" \
    HOSTPYTHON="$HOSTPYTHON" \
    CPPFLAGS="$CPPFLAGS" \
    CFLAGS="$CFLAGS" \
    LDFLAGS="$LDFLAGS"
  
  abul::log::info "Building Python..."
  make HOSTPYTHON="$HOSTPYTHON" -j"${ABUL_BUILD_THREADS}"
  
  abul::log::info "Installing Python..."
  make install
  
  popd >/dev/null
  
  abul::log::success "Cross-compiled Python built"
}

# Apply post-build patches
plugin::python::apply_patches() {
  abul::log::section "Applying patches"
  
  # Create environment patch script
  local envpatch_dir="${ABUL_OUTPUT_DIR}/etc/profile.d"
  mkdir -p "$envpatch_dir"
  
  cat > "${envpatch_dir}/python${PYTHON_VERSION}-envpatch.sh" <<EOF
# Python ${PYTHON_VERSION} environment setup for Android
export PATH=\$PREFIX/bin:\$PATH
export CC=clang
export CXX=clang++
export LDSHARED="\$CC -shared"
export CPPFLAGS="-I\$PREFIX/include -I\$PREFIX/include/${ABUL_TARGET_TRIPLE}"
export LDFLAGS="-L\$PREFIX/lib"
export PKG_CONFIG_PATH="\$PREFIX/lib/pkgconfig:\$PKG_CONFIG_PATH"
EOF
  
  abul::log::success "Patches applied"
}

# Create distribution archive
plugin::python::create_distribution() {
  abul::log::section "Creating distribution archive"
  
  local archive_name="python-${PYTHON_VERSION}-${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}.tar.gz"
  local archive_path
  
  archive_path=$(abul::plugin::create_archive "$archive_name" "$ABUL_OUTPUT_DIR")
  
  abul::log::success "Distribution archive created: $archive_path"
}

# Main plugin entry point
plugin::python::run() {
  # Parse plugin-specific arguments
  abul::plugin::parse_args "python" "$@"
  
  local python_api="$ABUL_ANDROID_API"
  local python_arch="$ABUL_TARGET_ARCH"
  local python_version=""
  local skip_host_build="false"
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api)
        python_api="$2"
        shift 2
        ;;
      --arch)
        python_arch="$2"
        shift 2
        ;;
      --skip-host-python)
        skip_host_build="true"
        shift
        ;;
      *)
        if [ -z "$python_version" ]; then
          python_version="$1"
          shift
        else
          abul::log::error "Unknown argument: $1"
          plugin::python::usage
          exit 1
        fi
        ;;
    esac
  done
  
  # Check host dependencies
  plugin::python::check_deps
  
  # Configure plugin
  plugin::python::config "$python_version"
  
  # Download sources
  plugin::python::download_sources
  
  # Setup or build host Python (check system first)
  plugin::python::setup_host_python "$skip_host_build"
  
  # Setup Android toolchain
  abul::toolchain::setup "$python_api" "$python_arch"
  
  # Build dependencies
  plugin::python::build_zlib
  plugin::python::build_bzip2
  plugin::python::build_libffi
  plugin::python::build_openssl
  plugin::python::build_xz
  plugin::python::build_ncurses
  plugin::python::build_readline
  plugin::python::build_gdbm
  plugin::python::build_sqlite
  
  # Build cross-compiled Python
  plugin::python::build_cross
  
  # Apply patches
  plugin::python::apply_patches
  
  # Create distribution
  plugin::python::create_distribution
  
  abul::log::section "Build Summary"
  abul::log::info "Python version: ${PYTHON_VERSION}"
  abul::log::info "Target: ${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}"
  abul::log::info "Output directory: ${ABUL_OUTPUT_DIR}"
  abul::log::info "Plugin workspace: ${ABUL_PLUGIN_WORKSPACE}"
}
