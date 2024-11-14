
<a href="https://github.com/chrischtel/zfitsio/releases"><img src="https://badgen.net/github/release/chrischtel/zfitsio" />   
   <a href="https://github.com/chrischtel/zfitsio#Apache-2.0-1-ov-file"><img src="https://badgen.net/github/license/chrischtel/zfitsio" />
   
> ⚠️ **Notice:** This project is a work in progress and is not yet stable for production use. Key features are still under development, and the API may change.

<p id="description">zfitsio is a lightweight (not yet powerful) Zig wrapper around the widely-used CFITSIO library designed to provide Zig developers with seamless access to FITS (Flexible Image Transport System) files. FITS is a standard file format used in astrophotography astronomy and scientific imaging. This project simplifies the process of reading manipulating and analyzing FITS data by wrapping core CFITSIO functions in a Zig-friendly interface allowing efficient data handling without complex setups.</p>

---
## 2. **Installation**
d
### Prerequisites
- **Zig**: Install latest version (0.13.0)

### Setup
1. Add `zfitsio` to your project by using the Zig package manager:
   
   ```sh
   zig fetch --save git+https://github.com/chrischtel/zfitsio#master

2. Add the following code to your `build.zig` file to link `zfitsio`

   ```zig
    const zfitsio_dep = b.dependency("zfitsio", .{
        .target = target,
        .optimize = optimize,
    });
    
    const zfitsio_artifact = zfitsio_dep.artifact("zfitsio");
    
    exe.root_module.addImport("zfitsio", zfitsio_dep.module("zfitsio"));
    exe.linkLibC();
    exe.linkLibrary(zfitsio_artifact);
  
---

## Supported Platforms

`zfitsio` aims to be cross-platform, but support may vary depending on your setup and dependencies. Below is the list of platforms currently supported:

- ~~**Linux** (tested on Ubuntu and other Debian-based distributions)~~
- ~~**macOS** (support for Intel and Apple Silicon architectures)~~
- **Windows** (support when building dependencies from source (built-in build proccess), systemwide-linkage not tested)

Please note that `zfitsio` relies on CFITSIO, which must be properly configured for each platform. Users are encouraged to report any platform-specific issues or contribute to enhancing cross-platform support.


---
