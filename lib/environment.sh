#!/usr/bin/env bash
# ABUL Environment Functions

# Check if required host packages are installed (Debian/Ubuntu)
abul::env::check_host_deps() {
  local deps=("$@")
  
  if [ ${#deps[@]} -eq 0 ]; then
    return 0
  fi
  
  abul::log::debug "Checking host dependencies..."
  
  local missing=()
  for pkg in "${deps[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
      missing+=("$pkg")
    fi
  done
  
  if [ ${#missing[@]} -ne 0 ]; then
    abul::log::error "Missing host packages:"
    printf '  - %s\n' "${missing[@]}" >&2
    echo
    echo "Install with:"
    echo "  sudo apt update && sudo apt install -y ${missing[*]}"
    echo
    return 1
  fi
  
  abul::log::success "Host dependencies satisfied"
}

# Set a build environment variable
abul::env::set() {
  local name="$1"
  local value="$2"
  
  export "$name=$value"
  abul::log::debug "Set env: $name=$value"
}

# Append to an environment variable
abul::env::append() {
  local name="$1"
  local value="$2"
  local separator="${3:-:}"
  
  if [ -z "${!name:-}" ]; then
    export "$name=$value"
  else
    export "$name=${!name}${separator}${value}"
  fi
  
  abul::log::debug "Append env: $name+=$value"
}

# Prepend to an environment variable
abul::env::prepend() {
  local name="$1"
  local value="$2"
  local separator="${3:-:}"
  
  if [ -z "${!name:-}" ]; then
    export "$name=$value"
  else
    export "$name=${value}${separator}${!name}"
  fi
  
  abul::log::debug "Prepend env: $name=$value+..."
}

# Save current environment
abul::env::save() {
  local output_file="$1"
  
  declare -px > "$output_file"
  abul::log::debug "Environment saved to: $output_file"
}

# Load environment from file
abul::env::load() {
  local input_file="$1"
  
  if [ ! -f "$input_file" ]; then
    abul::log::error "Environment file not found: $input_file"
    return 1
  fi
  
  source "$input_file"
  abul::log::debug "Environment loaded from: $input_file"
}
