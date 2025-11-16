#!/usr/bin/env bash
# ABUL Common Functions

# Initialize workspace directory structure
abul::common::init_workspace() {
  mkdir -p "$ABUL_WORKSPACE"
  abul::log::debug "Workspace initialized: $ABUL_WORKSPACE"
}

# Initialize plugin-specific workspace
abul::common::init_plugin_workspace() {
  local plugin_name="$1"
  
  export ABUL_PLUGIN_WORKSPACE="${ABUL_WORKSPACE}/${plugin_name}"
  export ABUL_DOWNLOADS_DIR="${ABUL_PLUGIN_WORKSPACE}/downloads"
  export ABUL_SRC_DIR="${ABUL_PLUGIN_WORKSPACE}/src"
  export ABUL_STAGING_DIR="${ABUL_PLUGIN_WORKSPACE}/staging"
  export ABUL_OUTPUT_DIR="${ABUL_PLUGIN_WORKSPACE}/output"
  export ABUL_BUILD_MARKERS_DIR="${ABUL_STAGING_DIR}/.built"
  
  mkdir -p "$ABUL_PLUGIN_WORKSPACE" \
           "$ABUL_DOWNLOADS_DIR" \
           "$ABUL_SRC_DIR" \
           "$ABUL_STAGING_DIR" \
           "$ABUL_OUTPUT_DIR" \
           "$ABUL_BUILD_MARKERS_DIR"
  
  abul::log::debug "Plugin workspace initialized: $ABUL_PLUGIN_WORKSPACE"
}

# Compute SHA256 checksum of a file
abul::common::sha256() {
  local file="$1"
  
  if [ ! -f "$file" ]; then
    abul::log::error "File not found for checksum: $file"
    return 1
  fi
  
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    # Fallback for systems without sha256sum
    openssl dgst -sha256 "$file" | awk '{print $2}'
  fi
}

# Check if a command exists
abul::common::command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Clean a build directory
abul::common::clean_builddir() {
  local dir="$1"
  
  if [ -d "$dir" ]; then
    abul::log::debug "Cleaning build directory: $dir"
    rm -rf "$dir"
  fi
}
