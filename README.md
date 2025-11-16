# ABUL - Android Build System

A modular, plugin-based framework for cross-compiling software for Android using the Android NDK.

## Features

- 🔌 **Plugin Architecture**: Easy-to-create plugins for different build targets
- 🛠️ **NDK Integration**: Automatic NDK download and toolchain setup
- 📦 **Build Caching**: Smart build markers prevent unnecessary rebuilds
- 🎯 **Multi-Architecture**: Support for aarch64, armv7a, x86_64, i686
- 🔧 **Customizable**: Override build parameters via environment variables
- 📝 **Comprehensive Logging**: Colored, timestamped logs with debug mode
- ⚡ **Parallel Builds**: Multi-threaded compilation support

## Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd abul

# Make the main script executable
chmod +x abul

# Optional: Add to PATH
echo 'export PATH="$PATH:'$(pwd)'"' >> ~/.bashrc
source ~/.bashrc
```

## Quick Start

```bash
# List available plugins
./abul --list-plugins

# Build Python 3.13.9 for Android
./abul python 3.13.9

# Build with custom settings
./abul --workspace /tmp/builds --jobs 8 python 3.13.9

# Build for specific architecture
./abul python --arch aarch64 --api 34 3.13.9

# Use custom environment variables
./abul --env PYTHON_ZLIB_VERSION=1.3.1 python 3.13.9
```

## Usage

```
abul [OPTIONS] <plugin> [plugin-args...]

Options:
  -h, --help              Show this help message
  -v, --verbose           Enable verbose logging
  -w, --workspace DIR     Set workspace directory (default: ~/abul-workspace)
  -j, --jobs N            Number of parallel jobs (default: nproc)
  --list-plugins          List available plugins
  --env KEY=VALUE         Set custom environment variable

Examples:
  abul python 3.13.9
  abul --workspace /tmp/builds python 3.13.9
  abul --env CUSTOM_VAR=value python 3.13.9
```

## Directory Structure

```
abul/
├── abul                    # Main entry point script
├── lib/                    # Core framework libraries
│   ├── common.sh          # Common utility functions
│   ├── logging.sh         # Logging functions
│   ├── download.sh        # Download management
│   ├── extract.sh         # Archive extraction
│   ├── environment.sh     # Environment variable management
│   ├── toolchain.sh       # Android NDK toolchain setup
│   └── plugin_base.sh     # Plugin base functions
├── plugins/               # Plugin directory
│   ├── python.sh         # Python build plugin
│   └── example.sh        # Example plugin
└── README.md             # This file
```

## Workspace Structure

When you run a plugin, ABUL creates the following workspace structure:

```
~/abul-workspace/          # Default workspace (configurable)
├── ndk/                   # Downloaded NDK (if not provided)
└── <plugin-name>/         # Plugin-specific workspace
    ├── downloads/         # Downloaded source archives
    ├── src/              # Extracted source code
    ├── staging/          # Built dependencies and libraries
    │   └── .built/       # Build markers (cache)
    ├── output/           # Final build output
    └── *.tar.gz          # Distribution archive
```

## Available Plugins

### Python Plugin

Cross-compile Python for Android with all dependencies.

```bash
# Basic usage
./abul python 3.13.9

# Custom architecture and API level
./abul python --arch aarch64 --api 34 3.13.9

# Custom dependency versions
./abul --env PYTHON_ZLIB_VERSION=1.3.1 python 3.13.9

# Show plugin help
./abul python --help
```

**Built-in dependencies:**
- zlib
- bzip2
- libffi
- OpenSSL
- xz
- ncurses
- readline
- gdbm
- SQLite

**Configuration via environment variables:**
- `PYTHON_ZLIB_VERSION` (default: 1.3.1)
- `PYTHON_LIBFFI_VERSION` (default: 3.5.2)
- `PYTHON_OPENSSL_VERSION` (default: 3.5.4)
- `PYTHON_XZ_VERSION` (default: 5.8.1)
- `PYTHON_NCURSES_VERSION` (default: 6.5)
- `PYTHON_READLINE_VERSION` (default: 8.3)
- `PYTHON_BZIP2_VERSION` (default: 1.0.8)
- `PYTHON_GDBM_VERSION` (default: 1.26)

## Creating a Plugin

Creating a new plugin is straightforward. Here's a minimal example:

### 1. Create Plugin File

Create `plugins/myproject.sh`:

```bash
#!/usr/bin/env bash
# ABUL Plugin: MyProject

# Plugin metadata
plugin::myproject::describe() {
  echo "Build MyProject for Android"
}

plugin::myproject::usage() {
  cat <<EOF
Usage: abul myproject [OPTIONS] <version>

Arguments:
  version                Version to build

Options:
  -h, --help             Show this help
  --api LEVEL            Android API level (default: 34)
  --arch ARCH            Target architecture (default: aarch64)
EOF
}

# Main plugin entry point
plugin::myproject::run() {
  # Parse arguments
  abul::plugin::parse_args "myproject" "$@"
  
  local version=""
  
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
    --disable-shared
  
  # Create distribution
  abul::plugin::create_archive \
    "myproject-${version}-${ABUL_TARGET_TRIPLE}${ABUL_ANDROID_API}.tar.gz" \
    "$ABUL_OUTPUT_DIR"
  
  abul::log::success "MyProject ${version} built successfully!"
}
```

### 2. Use Your Plugin

```bash
./abul myproject 1.0.0
```

## Plugin Development Guide

### Required Functions

Every plugin must implement:

1. **`plugin::<name>::run`** - Main entry point
2. **`plugin::<name>::describe`** - Short description (optional but recommended)
3. **`plugin::<name>::usage`** - Usage/help text (optional but recommended)

### Available Library Functions

#### Logging (`lib/logging.sh`)

```bash
abul::log::debug "Debug message"      # Only in verbose mode
abul::log::info "Info message"        # Normal message
abul::log::success "Success message"  # Green success message
abul::log::warn "Warning message"     # Yellow warning
abul::log::error "Error message"      # Red error
abul::log::fatal "Fatal error"        # Red error + exit
abul::log::section "Section Title"    # Cyan section header
```

#### Downloads (`lib/download.sh`)

```bash
# Simple download
abul::download::fetch \
  "https://example.com/file.tar.gz" \
  "${ABUL_DOWNLOADS_DIR}/file.tar.gz" \
  "Description"

# Download with checksum verification
abul::download::fetch_verify \
  "https://example.com/file.tar.gz" \
  "${ABUL_DOWNLOADS_DIR}/file.tar.gz" \
  "sha256checksum" \
  "Description"
```

#### Extraction (`lib/extract.sh`)

```bash
# Extract archive
abul::extract::archive \
  "${ABUL_DOWNLOADS_DIR}/file.tar.gz" \
  "${ABUL_SRC_DIR}/project" \
  "Description"

# Download and extract in one step
abul::extract::fetch_and_extract \
  "https://example.com/file.tar.gz" \
  "${ABUL_SRC_DIR}/project" \
  "Description"
```

#### Toolchain (`lib/toolchain.sh`)

```bash
# Setup Android toolchain
abul::toolchain::setup "$api" "$arch"

# After setup, these variables are available:
# - $CC, $CXX, $AR, $RANLIB, $STRIP
# - $CFLAGS, $CXXFLAGS, $CPPFLAGS, $LDFLAGS
# - $SYSROOT, $ABUL_TARGET_TRIPLE

# Get configure flags
abul::toolchain::get_host_flag   # Returns: --host=<triple>
abul::toolchain::get_build_flag  # Returns: --build=<native>
```

#### Build Helpers (`lib/plugin_base.sh`)

```bash
# Autotools build
abul::plugin::build_autotools \
  "component-name" \
  "${ABUL_SRC_DIR}/component" \
  --disable-shared \
  --enable-static

# CMake build
abul::plugin::build_cmake \
  "component-name" \
  "${ABUL_SRC_DIR}/component" \
  -DBUILD_SHARED_LIBS=OFF

# Build with markers (automatic caching)
abul::plugin::build_component \
  "component-name" \
  "${ABUL_DOWNLOADS_DIR}/component.tar.gz" \
  "${ABUL_SRC_DIR}/component" \
  abul::plugin::build_autotools \
  --disable-shared

# Create distribution archive
abul::plugin::create_archive \
  "output.tar.gz" \
  "${ABUL_OUTPUT_DIR}"
```

#### Build Markers (`lib/plugin_base.sh`)

```bash
# Check if built
if abul::plugin::is_built "component-name"; then
  echo "Already built"
fi

# Check with content matching
if abul::plugin::is_built_match "component" "version=1.0;arch=arm64"; then
  echo "Already built with same parameters"
fi

# Mark as built
abul::plugin::mark_built "component" "version=1.0;arch=arm64"

# Clear marker
abul::plugin::clear_marker "component"
```

### Environment Variables

#### Available to Plugins

- `ABUL_ROOT` - Framework root directory
- `ABUL_WORKSPACE` - Main workspace directory
- `ABUL_PLUGIN_WORKSPACE` - Plugin-specific workspace
- `ABUL_DOWNLOADS_DIR` - Downloads directory
- `ABUL_SRC_DIR` - Source directory
- `ABUL_STAGING_DIR` - Staging directory (dependencies)
- `ABUL_OUTPUT_DIR` - Output directory
- `ABUL_BUILD_MARKERS_DIR` - Build markers directory
- `ABUL_BUILD_THREADS` - Number of parallel build jobs
- `ABUL_VERBOSE` - Verbose mode (0 or 1)

#### Toolchain Variables (after `abul::toolchain::setup`)

- `ANDROID_NDK_ROOT` - NDK root directory
- `ABUL_TOOLCHAIN` - Toolchain directory
- `ABUL_TARGET_TRIPLE` - Target triple (e.g., aarch64-linux-android)
- `ABUL_ANDROID_API` - Android API level
- `CC`, `CXX`, `AR`, `RANLIB`, `STRIP` - Compiler tools
- `CFLAGS`, `CXXFLAGS`, `CPPFLAGS`, `LDFLAGS` - Build flags
- `SYSROOT` - Android sysroot
- `PKG_CONFIG_LIBDIR`, `PKG_CONFIG_PATH` - pkg-config paths

## Advanced Usage

### Custom Workspace

```bash
# Use a different workspace directory
./abul --workspace /mnt/ssd/builds python 3.13.9
```

### Parallel Builds

```bash
# Use specific number of jobs
./abul --jobs 16 python 3.13.9

# Or set environment variable
ABUL_BUILD_THREADS=16 ./abul python 3.13.9
```

### Verbose Mode

```bash
# Enable debug logging
./abul --verbose python 3.13.9

# Or set environment variable
ABUL_VERBOSE=1 ./abul python 3.13.9
```

### Custom NDK

```bash
# Use existing NDK
export ANDROID_NDK_ROOT=/path/to/ndk
./abul python 3.13.9

# Or specify NDK version
export ABUL_NDK_VERSION=r27d
./abul python 3.13.9
```

### Multiple Environment Variables

```bash
./abul \
  --env PYTHON_ZLIB_VERSION=1.3.1 \
  --env PYTHON_OPENSSL_VERSION=3.5.4 \
  --env CUSTOM_FLAG=value \
  python 3.13.9
```

## Troubleshooting

### Build Fails

1. **Enable verbose mode** to see detailed logs:
   ```bash
   ./abul --verbose python 3.13.9
   ```

2. **Clear build markers** to force rebuild:
   ```bash
   rm -rf ~/abul-workspace/<plugin>/staging/.built
   ```

3. **Clean workspace** for fresh build:
   ```bash
   rm -rf ~/abul-workspace/<plugin>
   ```

### Missing Dependencies

Install required build dependencies (Ubuntu/Debian):

```bash
sudo apt update && sudo apt install -y \
  build-essential clang llvm cmake git wget unzip pkg-config \
  automake autoconf libtool bison \
  libbz2-dev libsqlite3-dev libreadline-dev libncurses-dev \
  libffi-dev liblzma-dev zlib1g-dev libssl-dev \
  perl python3 texinfo autopoint po4a
```

### NDK Issues

If NDK download fails, manually download and set:

```bash
# Download NDK
wget https://dl.google.com/android/repository/android-ndk-r27d-linux.tar.xz
tar -xf android-ndk-r27d-linux.tar.xz

# Set environment variable
export ANDROID_NDK_ROOT=$(pwd)/android-ndk-r27d
./abul python 3.13.9
```

## Contributing

Contributions are welcome! To add a new plugin:

1. Create `plugins/<name>.sh` following the plugin template
2. Implement required functions
3. Test thoroughly
4. Submit a pull request

## License

[Your License Here]

## Credits

Created to simplify cross-compilation of software for Android devices.

## Support

For issues, questions, or contributions, please visit:
- Issue Tracker: [Your issue tracker URL]
- Documentation: [Your docs URL]
