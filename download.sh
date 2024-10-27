#!/run/current-system/sw/bin/zsh

set -e

# Define download URLs for the latest versions of cfitsio and zlib
CFITSIO_URL="https://heasarc.gsfc.nasa.gov/FTP/software/fitsio/c/cfitsio_latest.tar.gz"
ZLIB_URL="https://zlib.net/zlib-1.3.1.tar.gz"  # Replace with the latest stable zlib URL if this version is outdated

# Create a libs directory if it doesn't exist
mkdir -p libs
cd libs

# Download and extract cfitsio
echo "Downloading the latest cfitsio source..."
curl -LO $CFITSIO_URL
echo "Extracting cfitsio..."
tar -xzf cfitsio_latest.tar.gz
rm cfitsio_latest.tar.gz
mv cfitsio-* cfitsio

# Download and extract zlib
echo "Downloading the latest zlib source..."
curl -LO $ZLIB_URL
echo "Extracting zlib..."
tar -xzf zlib-*.tar.gz
rm zlib-*.tar.gz
mv zlib-* zlib

echo "Latest sources for cfitsio and zlib downloaded and extracted in 'libs' directory."
