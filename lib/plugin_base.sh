#!/usr/bin/env bash
# ABUL Plugin Base Functions
# Provides common functionality for all plugins

# Build marker management
# -----------------------

# Create a build marker with content
abul::plugin::mark_built() {
  local component_name="$1"
  shift
  local marker_content="$*"
  
  local marker_file="${ABUL_BUILD_MARKERS_DIR}/${component_name}.marker"
  local temp_file
  temp_file="$(mktemp "${ABUL_BUILD_MARKERS_DIR}/${component_name}.tmp.XXXX")"
  
  printf '%s\n' "$marker_content" > "$temp_file"
  mv "$temp_file" "$marker_file"
  
  abul::log::debug "Build marker created: ${component_name}"
}

# Check if component is built (marker exists)
abul::plugin::is_built() {
  local component_name="$1"
  local marker_file="${ABUL_BUILD_MARKERS_DIR}/${component_name}.marker"
  
  [ -f "$marker_file" ]
}

# Check if component is built and marker content matches
abul::plugin::is_built_match() {
  local component_name="$1"
  shift
  local expected_content="$*"
  
  local marker_file="${ABUL_BUILD_MARKERS_DIR}/${component_name}.marker"
  
  if [ ! -f "$marker_file" ]; then
    return 1
  fi
  
  local actual_content
  actual_content="$(cat "$marker_file")"
  
  [ "$actual_content" = "$expected_content" ]
}

# Clear build marker
abul::plugin::clear_marker() {
  local component_name="$1"
  local marker_file="${ABUL_BUILD_MARKERS_DIR}/${component_name}.marker"
  
  if [ -f "$marker_file" ]; then
    rm -f "$marker_file"
    abul::log::debug "Build marker cleared: ${component_name}"
  fi
}

# Autotools build helpers
# -----------------------

# Standard autotools configure and build
abul::plugin::build_autotools() {
  local component_name="$1"
  local src_dir="$2"
  shift 2
  local configure_args=("$@")
  
  abul::log::section "Building ${component_name}"
  
  if [ ! -d "$src_dir" ]; then
    abul::log::error "Source directory not found: $src_dir"
    return 1
  fi
  
  pushd "$src_dir" >/dev/null
  
  # Run autogen/autoreconf if configure doesn't exist
  if [ ! -x "./configure" ]; then
    if [ -x "./autogen.sh" ]; then
      abul::log::info "Running autogen.sh"
      ./autogen.sh
    elif [ -f "configure.ac" ] || [ -f "configure.in" ]; then
      abul::log::info "Running autoreconf"
      autoreconf -fi
    else
      abul::log::error "No configure script or autogen found"
      popd >/dev/null
      return 1
    fi
  fi
  
  # Configure
  abul::log::info "Configuring ${component_name}..."
  CC="$CC" \
  CXX="$CXX" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS" \
  CXXFLAGS="$CXXFLAGS" \
  CPPFLAGS="$CPPFLAGS" \
  LDFLAGS="$LDFLAGS" \
  ./configure \
    "$(abul::toolchain::get_host_flag)" \
    --prefix="$ABUL_STAGING_DIR" \
    "${configure_args[@]}"
  
  # Build
  abul::log::info "Building ${component_name}..."
  make -j"${ABUL_BUILD_THREADS}"
  
  # Install
  abul::log::info "Installing ${component_name}..."
  make install
  
  popd >/dev/null
  
  abul::log::success "${component_name} built successfully"
}

# CMake build helper
abul::plugin::build_cmake() {
  local component_name="$1"
  local src_dir="$2"
  shift 2
  local cmake_args=("$@")
  
  abul::log::section "Building ${component_name}"
  
  if [ ! -d "$src_dir" ]; then
    abul::log::error "Source directory not found: $src_dir"
    return 1
  fi
  
  local build_dir="${src_dir}/build"
  mkdir -p "$build_dir"
  
  pushd "$build_dir" >/dev/null
  
  # Configure
  abul::log::info "Configuring ${component_name} with CMake..."
  cmake \
    -DCMAKE_INSTALL_PREFIX="$ABUL_STAGING_DIR" \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_CXX_COMPILER="$CXX" \
    -DCMAKE_AR="$AR" \
    -DCMAKE_RANLIB="$RANLIB" \
    -DCMAKE_C_FLAGS="$CFLAGS" \
    -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
    -DCMAKE_SYSROOT="$SYSROOT" \
    -DCMAKE_FIND_ROOT_PATH="$ABUL_STAGING_DIR" \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
    "${cmake_args[@]}" \
    ..
  
  # Build
  abul::log::info "Building ${component_name}..."
  cmake --build . -j"${ABUL_BUILD_THREADS}"
  
  # Install
  abul::log::info "Installing ${component_name}..."
  cmake --install .
  
  popd >/dev/null
  
  abul::log::success "${component_name} built successfully"
}

# Generic component builder with marker support
abul::plugin::build_component() {
  local component_name="$1"
  local archive_path="$2"
  local src_dir="$3"
  shift 3
  local build_func="$1"
  shift
  local build_args=("$@")
  
  # Generate marker content
  local archive_hash
  archive_hash="$(abul::common::sha256 "$archive_path")"
  local marker_content="archive=${archive_hash};cflags=${CFLAGS};cppflags=${CPPFLAGS}"
  
  # Check if already built
  if abul::plugin::is_built_match "$component_name" "$marker_content"; then
    abul::log::info "Skipping ${component_name}: already built"
    return 0
  fi
  
  # Clean and extract
  abul::common::clean_builddir "$src_dir"
  abul::extract::archive "$archive_path" "$src_dir" "$component_name"
  
  # Build
  "$build_func" "$component_name" "$src_dir" "${build_args[@]}"
  
  # Mark as built
  abul::plugin::mark_built "$component_name" "$marker_content"
}

# Archive creation helper
abul::plugin::create_archive() {
  local archive_name="$1"
  local source_dir="$2"
  local dest_dir="${3:-$ABUL_PLUGIN_WORKSPACE}"
  
  local archive_path="${dest_dir}/${archive_name}"
  
  abul::log::info "Creating archive: ${archive_name}"
  
  pushd "$source_dir" >/dev/null
  
  case "$archive_name" in
    *.tar.gz|*.tgz)
      tar -czf "$archive_path" .
      ;;
    *.tar.xz)
      tar -cJf "$archive_path" .
      ;;
    *.tar.bz2)
      tar -cjf "$archive_path" .
      ;;
    *.zip)
      zip -qr "$archive_path" .
      ;;
    *)
      abul::log::error "Unknown archive format: $archive_name"
      popd >/dev/null
      return 1
      ;;
  esac
  
  popd >/dev/null
  
  abul::log::success "Archive created: $archive_path"
  echo "$archive_path"
}

# Plugin argument parser helper
abul::plugin::parse_args() {
  local plugin_name="$1"
  shift
  
  # Check for help flag
  for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ]; then
      if declare -f "plugin::${plugin_name}::usage" >/dev/null 2>&1; then
        "plugin::${plugin_name}::usage"
        exit 0
      else
        echo "Plugin '${plugin_name}' does not provide usage information"
        exit 0
      fi
    fi
  done
}
