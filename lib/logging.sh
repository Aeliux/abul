#!/usr/bin/env bash
# ABUL Logging Functions

# Color codes
readonly ABUL_COLOR_RESET='\033[0m'
readonly ABUL_COLOR_RED='\033[0;31m'
readonly ABUL_COLOR_GREEN='\033[0;32m'
readonly ABUL_COLOR_YELLOW='\033[0;33m'
readonly ABUL_COLOR_BLUE='\033[0;34m'
readonly ABUL_COLOR_CYAN='\033[0;36m'
readonly ABUL_COLOR_GRAY='\033[0;90m'

# Get timestamp
abul::log::timestamp() {
  date -Iseconds
}

# Log debug message (only in verbose mode)
abul::log::debug() {
  if [ "${ABUL_VERBOSE:-0}" = "1" ]; then
    printf '%s [%sDEBUG%s] %s\n' "$(abul::log::timestamp)" "$ABUL_COLOR_GRAY" "$ABUL_COLOR_RESET" "$*" >&2
  fi
}

# Log info message
abul::log::info() {
  printf '%s [%sINFO%s ] %s\n' "$(abul::log::timestamp)" "$ABUL_COLOR_BLUE" "$ABUL_COLOR_RESET" "$*"
}

# Log success message
abul::log::success() {
  printf '%s [%s OK %s ] %s\n' "$(abul::log::timestamp)" "$ABUL_COLOR_GREEN" "$ABUL_COLOR_RESET" "$*"
}

# Log warning message
abul::log::warn() {
  printf '%s [%sWARN%s ] %s\n' "$(abul::log::timestamp)" "$ABUL_COLOR_YELLOW" "$ABUL_COLOR_RESET" "$*" >&2
}

# Log error message
abul::log::error() {
  printf '%s [%sERROR%s] %s\n' "$(abul::log::timestamp)" "$ABUL_COLOR_RED" "$ABUL_COLOR_RESET" "$*" >&2
}

# Log fatal error and exit
abul::log::fatal() {
  printf '%s [%sFATAL%s] %s\n' "$(abul::log::timestamp)" "$ABUL_COLOR_RED" "$ABUL_COLOR_RESET" "$*" >&2
  exit 1
}

# Log section header
abul::log::section() {
  printf '\n%s=== %s ===%s\n\n' "$ABUL_COLOR_CYAN" "$*" "$ABUL_COLOR_RESET"
}
