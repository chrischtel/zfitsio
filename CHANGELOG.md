## v0.3.0 
### Added
This release is mainly focues on the Image Module.
- Added support for more FITSIO Datatypes:
  - UTBYTE
  - UTSHORT
  - UTINT
  - UTLONG

- Added new function `Image.calculateStatistics`
  - You can use then new ImageStats struct to get follwing statistical values:
    - min
    - max
    - mean
    - median
    - stddev
- Added more error handling functionality
  - With the `` function you can now log error formated error messages.

## v0.2.0 
### Added
- Header Manipulation
 - Write/update header keywords with support for:
   - String values (with proper FITS formatting)
   - Boolean values
   - Integer values
   - Float values
 - CardImage operations for header management
 - Security features to protect reserved FITS keywords
 - Header validation to prevent file corruption
 - Support for optional keyword comments
 - Memory safe string handling
 - Header keyword reading with error handling

- New `ImageOperations` struct for handling 2D image data from FITS files
- Support for 32-bit and 64-bit floating point image data
- Image section extraction with `getSection()` method
- World Coordinate System (WCS) support through `PhysicalCoords` struct
- Methods for reading/writing image data to FITS files
- Binary data export capability with `writeImage()`
- Integration tests for FITS file operations

- Data type support for FITS binary tables with `FitsType` enum
- Automatic conversion between FITS and Zig types
- Binary data parsing with proper byte ordering
- Generic `readFitsData` function supporting all FITS data types
- Unit tests for type conversions and data parsing

### Changed
- Improved error handling for FITS operations
- Enhanced memory management for string values
- Updated examples to demonstrate header manipulation
- Updated `build.zig` (refactored)

## [0.1.0] - 2024-03-xx
### Added
- Basic FITS file operations
 - Open/close FITS files
 - Read image data
 - Get HDU count
 - Get image dimensions
- Initial error handling
- Basic memory management