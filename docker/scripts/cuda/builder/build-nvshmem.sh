#!/bin/bash
set -Eeuo pipefail

# builds and installs NVSHMEM from source with coreweave patch
# expects CUDA_MAJOR, NVSHMEM_VERSION, NVSHMEM_DIR, NVSHMEM_CUDA_ARCHITECTURES env vars to be set

cd /tmp

# shellcheck source=/dev/null
source /usr/local/bin/setup-sccache

wget "https://developer.download.nvidia.com/compute/redist/nvshmem/${NVSHMEM_VERSION}/source/nvshmem_src_cuda12-all-all-${NVSHMEM_VERSION}.tar.gz" \
    -O "nvshmem_src_cuda${CUDA_MAJOR}.tar.gz"

tar -xf "nvshmem_src_cuda${CUDA_MAJOR}.tar.gz"

cd nvshmem_src

git apply /tmp/patches/cks_nvshmem"${NVSHMEM_VERSION}".patch

mkdir build
cd build

cmake \
    -G Ninja \
    -DNVSHMEM_PREFIX="${NVSHMEM_DIR}" \
    -DCMAKE_CUDA_ARCHITECTURES="${NVSHMEM_CUDA_ARCHITECTURES}" \
    -DNVSHMEM_PMIX_SUPPORT=0 \
    -DNVSHMEM_LIBFABRIC_SUPPORT=0 \
    -DNVSHMEM_IBRC_SUPPORT=1 \
    -DNVSHMEM_IBGDA_SUPPORT=1 \
    -DNVSHMEM_IBDEVX_SUPPORT=1 \
    -DNVSHMEM_SHMEM_SUPPORT=0 \
    -DNVSHMEM_USE_GDRCOPY=1 \
    -DNVSHMEM_MPI_SUPPORT=0 \
    -DNVSHMEM_USE_NCCL=0 \
    -DNVSHMEM_BUILD_TESTS=0 \
    -DNVSHMEM_BUILD_EXAMPLES=0 \
    -DGDRCOPY_HOME=/usr/local \
    -DNVSHMEM_DISABLE_CUDA_VMM=1 \
    ..

ninja -j"$(nproc)"
ninja install

# copy python wheel to /wheels
cp "${NVSHMEM_DIR}"/lib/python/dist/nvshmem4py_cu"${CUDA_MAJOR}"-*-cp"${PYTHON_VERSION/./}"-cp"${PYTHON_VERSION/./}"-manylinux_*.whl /wheels/

cd /tmp
rm -rf nvshmem_src*

if [ "${USE_SCCACHE}" = "true" ]; then
    echo "=== NVSHMEM build complete - sccache stats ==="
    sccache --show-stats
fi
