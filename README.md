<div align="center">

# 🌌 zfitsio

### A Modern Zig Wrapper for CFITSIO

[![Release](https://badgen.net/github/release/chrischtel/zfitsio)](https://github.com/chrischtel/zfitsio/releases)
[![License](https://badgen.net/github/license/chrischtel/zfitsio)](https://github.com/chrischtel/zfitsio#Apache-2.0-1-ov-file)
[![Zig](https://img.shields.io/badge/Zig-0.13.0-orange.svg)](https://ziglang.org/)
[![Status](https://img.shields.io/badge/Status-Alpha-yellow.svg)](https://github.com/chrischtel/zfitsio)

*Seamlessly work with astronomical FITS files in your Zig applications*

</div>

---

> 🚧 **Development Status:** This project is currently in alpha stage. The API is subject to change, and documentation is under active development. While functional, it's not yet recommended for production use.

## ✨ Features

- 📦 Lightweight wrapper around CFITSIO
- 🚀 Native Zig interface for FITS file operations
- 🛠️ Simple and intuitive API design
- 🔄 Support for reading and manipulating FITS data
- 🎯 Zero-cost abstractions where possible

## 🎯 Use Cases

- Astronomical data processing
- Scientific imaging applications
- FITS file manipulation and analysis
- Data pipeline integration
- Research and educational projects

## 📦 Installation

### Prerequisites

- **Zig**: Version 0.13.0 or later
- **C Compiler**: For CFITSIO compilation
- **Git**: For package fetching

### Quick Start

1. Add zfitsio to your project:
```sh
zig fetch --save git+https://github.com/chrischtel/zfitsio#master
```

2. Update your `build.zig`:
```zig
const zfitsio_dep = b.dependency("zfitsio", .{
    .target = target,
    .optimize = optimize,
});

const zfitsio_artifact = zfitsio_dep.artifact("zfitsio");

exe.root_module.addImport("zfitsio", zfitsio_dep.module("zfitsio"));
exe.linkLibC();
exe.linkLibrary(zfitsio_artifact);
```

## 🖥️ Platform Support

| Platform | Status | Notes |
|----------|--------|-------|
| Windows | ✅ Supported | Works with built-in build process |
| Linux | 🚧 In Progress | Testing on Debian-based systems |
| macOS | 🚧 In Progress | Both Intel and Apple Silicon |

## 📚 Basic Usage

```zig
const std = @import("std");
const zfitsio = @import("zfitsio");

pub fn main() !void {
    // Open a FITS file
    var fits = try zfitsio.FitsFile.open("example.fits", .read);
    defer fits.close();

    // Read header information
    const header = try fits.readHeader();
    
    // More examples coming soon...
}
```

## 🗺️ Roadmap

- [ ] Complete cross-platform support
- [ ] Comprehensive documentation
- [ ] Extended example collection
- [ ] Performance optimizations
- [ ] Additional FITS operations support
- [ ] Testing framework
- [ ] CI/CD pipeline

## 🤝 Contributing

Contributions are welcome! Here's how you can help:

- Report bugs and issues
- Submit pull requests
- Improve documentation
- Share usage examples
- Test on different platforms

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- CFITSIO development team
- Zig community
- All contributors

---

<div align="center">

**[Website](https://github.com/chrischtel/zfitsio)** • 
**[Documentation](https://github.com/chrischtel/zfitsio/wiki)** • 
**[Issue Tracker](https://github.com/chrischtel/zfitsio/issues)**

</div>
