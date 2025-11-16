#!/usr/bin/env bash
# ABUL Plugin: Example
# A simple example plugin demonstrating the plugin architecture

# Plugin metadata
plugin::example::describe() {
  echo "Example plugin demonstrating ABUL plugin architecture"
}

plugin::example::usage() {
  cat <<EOF
ABUL Example Plugin

Usage: abul example [OPTIONS] [message]

Arguments:
  message                Optional message to display (default: "Hello from ABUL!")

Options:
  -h, --help             Show this help message
  --api LEVEL            Android API level (default: 34)
  --arch ARCH            Target architecture (default: aarch64)
  --uppercase            Convert message to uppercase

Examples:
  abul example
  abul example "Custom message"
  abul example --uppercase "hello world"
  abul example --api 34 --arch aarch64 "Building for Android"

EOF
}

# Main plugin entry point
plugin::example::run() {
  # Parse plugin-specific arguments
  abul::plugin::parse_args "example" "$@"
  
  local message="Hello from ABUL!"
  local uppercase=false
  local api="$ABUL_ANDROID_API"
  local arch="$ABUL_TARGET_ARCH"
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api)
        api="$2"
        shift 2
        ;;
      --arch)
        arch="$2"
        shift 2
        ;;
      --uppercase)
        uppercase=true
        shift
        ;;
      *)
        message="$1"
        shift
        ;;
    esac
  done
  
  # Display plugin information
  abul::log::section "Example Plugin"
  
  abul::log::info "Plugin workspace: ${ABUL_PLUGIN_WORKSPACE}"
  abul::log::info "Downloads directory: ${ABUL_DOWNLOADS_DIR}"
  abul::log::info "Source directory: ${ABUL_SRC_DIR}"
  abul::log::info "Staging directory: ${ABUL_STAGING_DIR}"
  abul::log::info "Output directory: ${ABUL_OUTPUT_DIR}"
  
  # Setup toolchain (demonstrates toolchain usage)
  abul::log::section "Toolchain Setup"
  abul::toolchain::setup "$api" "$arch"
  
  abul::log::info "Compiler: $CC"
  abul::log::info "Target: ${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}"
  abul::log::info "Sysroot: $SYSROOT"
  
  # Process message
  abul::log::section "Message Processing"
  
  if [ "$uppercase" = true ]; then
    message="$(echo "$message" | tr '[:lower:]' '[:upper:]')"
  fi
  
  abul::log::success "Message: $message"
  
  # Create example output file
  abul::log::section "Creating Output"
  
  local output_file="${ABUL_OUTPUT_DIR}/message.txt"
  cat > "$output_file" <<EOF
ABUL Example Plugin Output
==========================

Message: $message
Target: ${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}
Build Date: $(date -Iseconds)
Workspace: ${ABUL_PLUGIN_WORKSPACE}

This is a demonstration of the ABUL plugin architecture.
You can create your own plugins by following this template!
EOF
  
  abul::log::success "Output written to: $output_file"
  
  # Demonstrate build marker usage
  abul::log::section "Build Markers"
  
  local marker_name="example-build"
  local marker_content="message=${message};timestamp=$(date +%s)"
  
  if abul::plugin::is_built_match "$marker_name" "$marker_content"; then
    abul::log::info "Build marker matches (already built)"
  else
    abul::log::info "Creating build marker..."
    abul::plugin::mark_built "$marker_name" "$marker_content"
    abul::log::success "Build marker created"
  fi
  
  # Demonstrate archive creation
  abul::log::section "Creating Archive"
  
  local archive_name="example-output-${ABUL_TARGET_TRIPLE}${api}.tar.gz"
  local archive_path
  
  archive_path=$(abul::plugin::create_archive "$archive_name" "$ABUL_OUTPUT_DIR")
  
  abul::log::success "Archive created: $archive_path"
  
  # Summary
  abul::log::section "Plugin Complete"
  abul::log::info "This example demonstrated:"
  abul::log::info "  ✓ Plugin metadata (describe, usage)"
  abul::log::info "  ✓ Argument parsing"
  abul::log::info "  ✓ Workspace directories"
  abul::log::info "  ✓ Toolchain setup"
  abul::log::info "  ✓ Logging functions"
  abul::log::info "  ✓ Build markers"
  abul::log::info "  ✓ Archive creation"
  
  abul::log::success "Example plugin execution completed!"
}
