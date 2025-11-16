#!/usr/bin/env bash
# ABUL Extract Functions

# Extract archive to destination
abul::extract::archive() {
  local archive="$1"
  local dest_dir="$2"
  local description="${3:-$(basename "$archive")}"
  
  if [ ! -f "$archive" ]; then
    abul::log::error "Archive not found: $archive"
    return 1
  fi
  
  if [ -d "$dest_dir" ]; then
    abul::log::info "Already extracted: $description"
    return 0
  fi
  
  abul::log::info "Extracting: $description"
  abul::log::debug "Archive: $archive"
  abul::log::debug "Destination: $dest_dir"
  
  local parent_dir
  parent_dir="$(dirname "$dest_dir")"
  mkdir -p "$parent_dir"
  
  # Create temporary extraction directory
  local temp_extract="${parent_dir}/.extract_${RANDOM}_$$"
  mkdir -p "$temp_extract"
  
  # Extract based on file extension
  case "$archive" in
    *.tar.xz)
      tar -xJf "$archive" -C "$temp_extract" || {
        rm -rf "$temp_extract"
        abul::log::error "Failed to extract: $archive"
        return 1
      }
      ;;
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$temp_extract" || {
        rm -rf "$temp_extract"
        abul::log::error "Failed to extract: $archive"
        return 1
      }
      ;;
    *.tar.bz2|*.tbz2)
      tar -xjf "$archive" -C "$temp_extract" || {
        rm -rf "$temp_extract"
        abul::log::error "Failed to extract: $archive"
        return 1
      }
      ;;
    *.zip)
      unzip -q "$archive" -d "$temp_extract" || {
        rm -rf "$temp_extract"
        abul::log::error "Failed to extract: $archive"
        return 1
      }
      ;;
    *)
      rm -rf "$temp_extract"
      abul::log::error "Unknown archive format: $archive"
      return 1
      ;;
  esac
  
  # Check if extraction created a single top-level directory
  local extracted_items
  extracted_items=($(ls -A "$temp_extract"))
  
  if [ ${#extracted_items[@]} -eq 1 ] && [ -d "$temp_extract/${extracted_items[0]}" ]; then
    # Single directory extracted - move it to destination
    mv "$temp_extract/${extracted_items[0]}" "$dest_dir"
    rm -rf "$temp_extract"
  else
    # Multiple items extracted - the temp dir becomes the destination
    mv "$temp_extract" "$dest_dir"
  fi
  
  abul::log::success "Extracted: $description"
}

# Download and extract in one step
abul::extract::fetch_and_extract() {
  local url="$1"
  local dest_dir="$2"
  local description="${3:-$(basename "$url")}"
  
  local archive="${ABUL_DOWNLOADS_DIR}/$(basename "$url")"
  
  # Download
  abul::download::fetch "$url" "$archive" "$description"
  
  # Extract
  abul::extract::archive "$archive" "$dest_dir" "$description"
}
