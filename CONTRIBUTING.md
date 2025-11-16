# Contributing to ABUL

Thank you for your interest in contributing to ABUL (Android Build System)! This guide will help you create plugins, improve the framework, and contribute effectively.

## Table of Contents
1. [Getting Started](#getting-started)
2. [Creating a Plugin](#creating-a-plugin)
3. [Plugin Best Practices](#plugin-best-practices)
4. [Testing Your Plugin](#testing-your-plugin)
5. [Code Style](#code-style)
6. [Submitting Changes](#submitting-changes)

## Getting Started

### Prerequisites
```bash
# Clone the repository
git clone <repo-url>
cd abul

# Make executable
chmod +x abul

# Test the framework
./abul --list-plugins
./abul example "test"
```

### Understanding the Architecture

```
Core Framework (lib/)
├── common.sh       → Utilities (SHA256, workspace, clean)
├── logging.sh      → Logging functions (info, error, etc.)
├── download.sh     → Download management
├── extract.sh      → Archive extraction
├── environment.sh  → Environment variables
├── toolchain.sh    → Android NDK/toolchain
└── plugin_base.sh  → Plugin helpers

Your Plugin (plugins/)
└── myplugin.sh     → Your project-specific logic
```

## Creating a Plugin

### Step 1: Create Plugin File

Create `plugins/myplugin.sh`:

```bash
#!/usr/bin/env bash
# ABUL Plugin: MyPlugin
# Description of what this plugin builds

# Required: Plugin description (short, one-line)
plugin::myplugin::describe() {
  echo "Build MyProject for Android"
}

# Optional but recommended: Usage help
plugin::myplugin::usage() {
  cat <<EOF
ABUL MyPlugin

Usage: abul myplugin [OPTIONS] <version>

Arguments:
  version                Version to build (e.g., 1.0.0)

Options:
  -h, --help             Show this help message
  --api LEVEL            Android API level (default: 34)
  --arch ARCH            Target architecture (default: aarch64)

Examples:
  abul myplugin 1.0.0
  abul myplugin --arch armv7a 1.0.0

EOF
}

# Required: Main plugin entry point
plugin::myplugin::run() {
  # Parse plugin arguments
  abul::plugin::parse_args "myplugin" "$@"
  
  local version=""
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --api)
        ABUL_ANDROID_API="$2"
        shift 2
        ;;
      --arch)
        ABUL_TARGET_ARCH="$2"
        shift 2
        ;;
      *)
        version="$1"
        shift
        ;;
    esac
  done
  
  # Validate
  if [ -z "$version" ]; then
    abul::log::error "Version not specified"
    plugin::myplugin::usage
    exit 1
  fi
  
  # Setup toolchain
  abul::toolchain::setup
  
  # Download source
  abul::download::fetch \
    "https://example.com/myproject-${version}.tar.gz" \
    "${ABUL_DOWNLOADS_DIR}/myproject-${version}.tar.gz" \
    "MyProject ${version}"
  
  # Extract
  local src_dir="${ABUL_SRC_DIR}/myproject-${version}"
  abul::extract::archive \
    "${ABUL_DOWNLOADS_DIR}/myproject-${version}.tar.gz" \
    "$src_dir" \
    "MyProject ${version}"
  
  # Build (autotools example)
  abul::plugin::build_autotools \
    "myproject-${version}" \
    "$src_dir" \
    --disable-shared \
    --enable-static
  
  # Create distribution
  abul::plugin::create_archive \
    "myproject-${version}-${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}.tar.gz" \
    "$ABUL_OUTPUT_DIR"
  
  abul::log::success "MyProject ${version} built successfully!"
}
```

### Step 2: Test Your Plugin

```bash
# Test help
./abul myplugin --help

# Test execution
./abul myplugin 1.0.0

# Test with options
./abul --verbose myplugin --arch aarch64 1.0.0
```

## Plugin Best Practices

### 1. Naming Conventions

```bash
# Plugin file: plugins/projectname.sh
# Functions: plugin::projectname::*

# Good
plugin::nodejs::run()
plugin::python::build_zlib()

# Bad
nodejs_run()           # Missing namespace
plugin::nodejs_run()   # Wrong separator
```

### 2. Use Framework Functions

```bash
# Good - Use framework
abul::log::info "Building..."
abul::download::fetch "$url" "$output"
abul::toolchain::setup

# Bad - Reinvent the wheel
echo "Building..."     # No timestamp, color
wget "$url"            # No error handling, caching
export CC=...          # Manual toolchain setup
```

### 3. Error Handling

```bash
# Good
if [ -z "$version" ]; then
  abul::log::error "Version required"
  plugin::myplugin::usage
  exit 1
fi

# Bad
# Silently continue without validation
```

### 4. Configuration

```bash
# Good - Use environment variables with defaults
MY_PLUGIN_VERSION="${MY_PLUGIN_VERSION:-1.0.0}"
MY_PLUGIN_OPTION="${MY_PLUGIN_OPTION:-default}"

# Users can override:
# ./abul --env MY_PLUGIN_VERSION=2.0.0 myplugin
```

### 5. Build Markers

```bash
# For simple autotools builds - automatic markers
abul::plugin::build_component \
  "component" \
  "$archive" \
  "$src_dir" \
  abul::plugin::build_autotools

# For custom builds - manual markers
if abul::plugin::is_built_match "component" "version=${ver};flags=${CFLAGS}"; then
  abul::log::info "Skipping component: already built"
  return 0
fi

# ... build steps ...

abul::plugin::mark_built "component" "version=${ver};flags=${CFLAGS}"
```

### 6. Logging Levels

```bash
# Use appropriate log levels
abul::log::debug "Detailed debug info"      # Only in --verbose
abul::log::info "Normal progress updates"   # Always shown
abul::log::success "Task completed"         # Positive feedback
abul::log::warn "Non-fatal warning"         # Warning
abul::log::error "Error occurred"           # Error (continues)
abul::log::fatal "Critical error"           # Error + exit

# Use sections for major steps
abul::log::section "Building Dependencies"
```

### 7. Workspace Usage

```bash
# Available directories (created automatically)
${ABUL_DOWNLOADS_DIR}        # For downloads
${ABUL_SRC_DIR}              # For extracted sources
${ABUL_STAGING_DIR}          # For built dependencies
${ABUL_OUTPUT_DIR}           # For final output
${ABUL_BUILD_MARKERS_DIR}    # For build markers

# Build dependencies go to staging
./configure --prefix="$ABUL_STAGING_DIR"

# Final output goes to output
./configure --prefix="$ABUL_OUTPUT_DIR"
```

## Testing Your Plugin

### Manual Testing

```bash
# 1. Help text
./abul myplugin --help

# 2. Basic execution
./abul myplugin 1.0.0

# 3. With options
./abul myplugin --arch aarch64 --api 34 1.0.0

# 4. Verbose mode
./abul --verbose myplugin 1.0.0

# 5. Custom workspace
./abul --workspace /tmp/test myplugin 1.0.0

# 6. Environment override
./abul --env CUSTOM_VAR=value myplugin 1.0.0
```

### Testing Checklist

- [ ] Plugin appears in `--list-plugins`
- [ ] Help text displays correctly
- [ ] Downloads work
- [ ] Extraction works
- [ ] Build succeeds
- [ ] Output archive created
- [ ] Build markers work (second run skips built components)
- [ ] Clean build works (after removing markers)
- [ ] Verbose mode shows debug output
- [ ] Errors are handled gracefully

### Testing Build Markers

```bash
# First build (should build everything)
./abul myplugin 1.0.0

# Second build (should skip built components)
./abul myplugin 1.0.0
# Should see: "Skipping X: already built"

# Force rebuild
rm -rf ~/abul-workspace/myplugin/staging/.built
./abul myplugin 1.0.0
# Should rebuild everything
```

## Code Style

### Shell Script Style

```bash
# Use bash strict mode (already in main script)
set -euo pipefail
shopt -s extglob

# Use double quotes for variables
local version="$1"              # Good
local version=$1                # Bad

# Use $(command) not `command`
local result="$(date +%s)"      # Good
local result=`date +%s`         # Bad

# Check variables exist
if [ -z "${VAR:-}" ]; then      # Good
if [ -z "$VAR" ]; then          # Bad (fails with set -u)

# Use [[ ]] for tests
if [[ "$a" == "$b" ]]; then     # Good
if [ "$a" == "$b" ]; then       # OK but less features

# Use local for function variables
function foo() {
  local bar="value"             # Good
  bar="value"                   # Bad (global)
}
```

### Function Documentation

```bash
# Document complex functions
# Build custom dependency with special flags
# Args:
#   $1 - component name
#   $2 - version
#   $3+ - configure flags
plugin::myplugin::build_custom() {
  local component="$1"
  local version="$2"
  shift 2
  
  # Implementation...
}
```

### Variable Naming

```bash
# Plugin-specific: UPPERCASE with plugin prefix
MY_PLUGIN_VERSION="1.0.0"
MY_PLUGIN_OPTION="value"

# Local variables: lowercase
local version="$1"
local src_dir="${ABUL_SRC_DIR}/src"

# Framework variables: ABUL_ prefix (don't create these)
ABUL_DOWNLOADS_DIR
ABUL_STAGING_DIR
```

## Submitting Changes

### Before Submitting

1. **Test thoroughly** using checklist above
2. **Update documentation** if adding features
3. **Follow code style** guidelines
4. **Add comments** for complex logic
5. **Test on clean workspace**

### Commit Message Format

```
[plugin] Short description (50 chars or less)

Longer explanation of what changed and why (if needed).
Include any breaking changes or important notes.

- Bullet points for multiple changes
- Keep lines under 72 characters
```

Examples:
```
[python] Add support for Python 3.12

[core] Improve error handling in download.sh

[docs] Update plugin creation guide

[plugin] Add Node.js cross-compilation support
```

### Pull Request Template

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] New plugin
- [ ] Core framework improvement
- [ ] Bug fix
- [ ] Documentation
- [ ] Other (describe)

## Testing
- [ ] Tested on clean workspace
- [ ] Help text displays correctly
- [ ] Build succeeds
- [ ] Build markers work
- [ ] Documentation updated

## Additional Notes
Any other relevant information
```

## Getting Help

### Resources
- **README.md**: Comprehensive user guide
- **QUICKSTART.md**: Quick start guide
- **MIGRATION.md**: Migration from old scripts
- **plugins/example.sh**: Full-featured example
- **plugins/python.sh**: Real-world complex example

### Questions?
- Open an issue for questions
- Check existing plugins for examples
- Read the core library code (`lib/`)

## Plugin Ideas

Looking for inspiration? Here are some plugin ideas:

### Easy Plugins (< 100 lines)
- SQLite
- cURL
- libjpeg/libpng
- zstd
- brotli

### Medium Plugins (100-200 lines)
- Node.js
- Ruby
- Go toolchain
- PHP
- FFmpeg

### Advanced Plugins (200+ lines)
- LLVM/Clang
- GCC
- Qt framework
- OpenCV
- Chromium

## Thank You!

Your contributions make ABUL better for everyone. Whether it's a new plugin, bug fix, documentation improvement, or feature enhancement, we appreciate your effort!

Happy building! 🚀
