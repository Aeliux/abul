#!/usr/bin/env bash
# ABUL Android Toolchain Functions

# NDK configuration
ABUL_NDK_VERSION="${ABUL_NDK_VERSION:-r27c}"
ABUL_ANDROID_API="${ABUL_ANDROID_API:-34}"
ABUL_TARGET_ARCH="${ABUL_TARGET_ARCH:-aarch64}"
ABUL_HOST_TAG="${ABUL_HOST_TAG:-linux-x86_64}"

# Derived values
ABUL_TARGET_TRIPLE="${ABUL_TARGET_ARCH}-linux-android"

# Ensure Android NDK is available
abul::toolchain::ensure_ndk() {
  # Check if ANDROID_NDK_ROOT is already set and valid
  if [ -n "${ANDROID_NDK_ROOT:-}" ] && [ -d "$ANDROID_NDK_ROOT" ]; then
    abul::log::info "Using existing NDK: $ANDROID_NDK_ROOT"
    return 0
  fi
  
  # Check workspace for downloaded NDK
  local ndk_dir="${ABUL_WORKSPACE}/ndk/android-ndk-${ABUL_NDK_VERSION}"
  if [ -d "$ndk_dir" ]; then
    export ANDROID_NDK_ROOT="$ndk_dir"
    abul::log::info "Using NDK from workspace: $ANDROID_NDK_ROOT"
    return 0
  fi
  
  # Download NDK if not found
  local ndk_url="https://dl.google.com/android/repository/android-ndk-${ABUL_NDK_VERSION}-linux.tar.xz"
  local ndk_archive="${ABUL_DOWNLOADS_DIR}/android-ndk-${ABUL_NDK_VERSION}-linux.tar.xz"
  
  abul::log::info "Downloading Android NDK ${ABUL_NDK_VERSION}..."
  abul::download::fetch "$ndk_url" "$ndk_archive" "Android NDK ${ABUL_NDK_VERSION}"
  
  # Extract NDK
  abul::log::info "Extracting Android NDK..."
  mkdir -p "$(dirname "$ndk_dir")"
  tar -xJf "$ndk_archive" -C "$(dirname "$ndk_dir")"
  
  if [ ! -d "$ndk_dir" ]; then
    abul::log::fatal "NDK extraction failed. Expected directory: $ndk_dir"
  fi
  
  export ANDROID_NDK_ROOT="$ndk_dir"
  abul::log::success "NDK ready: $ANDROID_NDK_ROOT"
}

# Setup Android toolchain environment
abul::toolchain::setup() {
  local api="${1:-$ABUL_ANDROID_API}"
  local arch="${2:-$ABUL_TARGET_ARCH}"
  
  # Ensure NDK is available
  abul::toolchain::ensure_ndk
  
  # Set target triple based on architecture
  case "$arch" in
    aarch64|arm64)
      ABUL_TARGET_TRIPLE="aarch64-linux-android"
      ;;
    armv7a|armv7|arm)
      ABUL_TARGET_TRIPLE="armv7a-linux-androideabi"
      ;;
    x86_64|x64)
      ABUL_TARGET_TRIPLE="x86_64-linux-android"
      ;;
    i686|x86)
      ABUL_TARGET_TRIPLE="i686-linux-android"
      ;;
    *)
      abul::log::fatal "Unknown architecture: $arch"
      ;;
  esac
  
  export ABUL_TARGET_TRIPLE
  export ABUL_ANDROID_API="$api"
  
  # Locate toolchain
  local toolchain="${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/${ABUL_HOST_TAG}"
  if [ ! -d "$toolchain" ]; then
    abul::log::fatal "Toolchain not found: $toolchain"
  fi
  
  export ABUL_TOOLCHAIN="$toolchain"
  
  # Setup compiler and tools
  export CC="${toolchain}/bin/${ABUL_TARGET_TRIPLE}${api}-clang"
  export CXX="${toolchain}/bin/${ABUL_TARGET_TRIPLE}${api}-clang++"
  export AR="${toolchain}/bin/llvm-ar"
  export AS="${toolchain}/bin/llvm-as"
  export LD="${toolchain}/bin/ld"
  export RANLIB="${toolchain}/bin/llvm-ranlib"
  export STRIP="${toolchain}/bin/llvm-strip"
  export NM="${toolchain}/bin/llvm-nm"
  export OBJDUMP="${toolchain}/bin/llvm-objdump"
  
  # Setup sysroot
  export SYSROOT="${toolchain}/sysroot"
  
  # Setup build flags
  export CFLAGS="${CFLAGS:---sysroot=${SYSROOT} -fPIC}"
  export CXXFLAGS="${CXXFLAGS:---sysroot=${SYSROOT} -fPIC}"
  export CPPFLAGS="${CPPFLAGS:--I${ABUL_STAGING_DIR}/include}"
  export LDFLAGS="${LDFLAGS:---sysroot=${SYSROOT} -L${ABUL_STAGING_DIR}/lib}"
  
  # Setup pkg-config
  export PKG_CONFIG_LIBDIR="${ABUL_STAGING_DIR}/lib/pkgconfig:${ABUL_STAGING_DIR}/share/pkgconfig"
  export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}:${PKG_CONFIG_PATH:-}"
  
  abul::log::success "Toolchain configured"
  abul::log::debug "Target: ${ABUL_TARGET_TRIPLE}${api}"
  abul::log::debug "CC: $CC"
  abul::log::debug "Staging: $ABUL_STAGING_DIR"
}

# Get configure host flag for autotools
abul::toolchain::get_host_flag() {
  echo "--host=${ABUL_TARGET_TRIPLE}"
}

# Get build flag for autotools (native build system)
abul::toolchain::get_build_flag() {
  echo "--build=$(uname -m)-linux-gnu"
}
