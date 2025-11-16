# ABUL Quick Start Guide

## Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd abul

# Make the main script executable
chmod +x abul
```

## Basic Usage

```bash
# List available plugins
./abul --list-plugins

# Get help
./abul --help
./abul python --help

# Build Python 3.13.9
./abul python 3.13.9
```

## Your First Plugin

Create `plugins/hello.sh`:

```bash
#!/usr/bin/env bash

plugin::hello::describe() {
  echo "A simple hello world plugin"
}

plugin::hello::run() {
  abul::plugin::parse_args "hello" "$@"
  
  local name="${1:-World}"
  
  abul::log::section "Hello Plugin"
  abul::log::success "Hello, ${name}!"
  
  echo "Hello, ${name}!" > "${ABUL_OUTPUT_DIR}/greeting.txt"
  abul::log::info "Greeting saved to: ${ABUL_OUTPUT_DIR}/greeting.txt"
}
```

Run it:

```bash
./abul hello "ABUL Framework"
```

## Common Tasks

### Build for Different Architecture

```bash
./abul python --arch armv7a 3.13.9
```

### Custom Workspace

```bash
./abul --workspace /tmp/my-builds python 3.13.9
```

### Enable Debug Logging

```bash
./abul --verbose python 3.13.9
```

### Set Custom Environment Variables

```bash
./abul --env PYTHON_ZLIB_VERSION=1.3.1 python 3.13.9
```

## Next Steps

- Read the [full README](README.md) for comprehensive documentation
- Check out the [example plugin](plugins/example.sh) for advanced features
- Study the [Python plugin](plugins/python.sh) for a real-world example
