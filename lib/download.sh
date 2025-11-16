#!/usr/bin/env bash
# ABUL Download Functions

# Download a file if it doesn't exist
abul::download::fetch() {
  local url="$1"
  local output="$2"
  local description="${3:-$(basename "$output")}"
  
  if [ -f "$output" ]; then
    abul::log::info "Already downloaded: $description"
    return 0
  fi
  
  abul::log::info "Downloading: $description"
  abul::log::debug "URL: $url"
  abul::log::debug "Output: $output"
  
  # Create parent directory if needed
  mkdir -p "$(dirname "$output")"
  
  # Download with wget or curl
  if abul::common::command_exists wget; then
    wget -c -O "$output" "$url" || {
      abul::log::error "Download failed: $url"
      rm -f "$output"
      return 1
    }
  elif abul::common::command_exists curl; then
    curl -L -C - -o "$output" "$url" || {
      abul::log::error "Download failed: $url"
      rm -f "$output"
      return 1
    }
  else
    abul::log::fatal "Neither wget nor curl found. Please install one of them."
  fi
  
  abul::log::success "Downloaded: $description"
}

# Download with checksum verification
abul::download::fetch_verify() {
  local url="$1"
  local output="$2"
  local expected_sha256="$3"
  local description="${4:-$(basename "$output")}"
  
  # Download file
  abul::download::fetch "$url" "$output" "$description"
  
  # Verify checksum
  local actual_sha256
  actual_sha256="$(abul::common::sha256 "$output")"
  
  if [ "$actual_sha256" != "$expected_sha256" ]; then
    abul::log::error "Checksum mismatch for $description"
    abul::log::error "Expected: $expected_sha256"
    abul::log::error "Actual:   $actual_sha256"
    rm -f "$output"
    return 1
  fi
  
  abul::log::debug "Checksum verified: $description"
}
