#!/bin/bash
set -Eeuo pipefail

# builds and installs gdrcopy from source

# shellcheck source=/dev/null
source /usr/local/bin/setup-sccache

git clone https://github.com/NVIDIA/gdrcopy.git
cd gdrcopy

CC="sccache gcc" CXX="sccache g++" PREFIX=/usr/local DESTLIB=/usr/local/lib make lib_install

cp src/libgdrapi.so.2.* /usr/lib64/
ldconfig

cd ..
rm -rf gdrcopy

if [ "${USE_SCCACHE}" = "true" ]; then
    echo "=== gdrcopy build complete - sccache stats ==="
    sccache --show-stats
fi
