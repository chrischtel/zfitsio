# Changelog
All notable changes to zfitsio will be documented in this file.

## [Unreleased] - v0.2.0
### Added
- Header Manipulation
  - Write/update header keywords with support for:
    - String values (with proper FITS formatting)
    - Boolean values
    - Integer values
    - Float values
  - Support for optional keyword comments
  - Memory safe string handling
  - Header keyword reading with error handling

### Changed
- Improved error handling for FITS operations
- Enhanced memory management for string values

## [0.1.0] - 2024-03-xx
### Added
- Basic FITS file operations
  - Open/close FITS files
  - Read image data
  - Get HDU count
  - Get image dimensions
- Initial error handling
- Basic memory management