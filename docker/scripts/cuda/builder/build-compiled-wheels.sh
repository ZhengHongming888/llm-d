#!/bin/bash
set -Eeuo pipefail

# builds compiled extension wheels (FlashInfer, DeepEP, DeepGEMM, pplx-kernels)
# expects VIRTUAL_ENV, CUDA_MAJOR, NVSHMEM_DIR, DEEPEP_*, DEEPGEMM_*, PPLX_KERNELS_* env vars

# shellcheck source=/dev/null
source "${VIRTUAL_ENV}/bin/activate"
# shellcheck source=/dev/null
source /usr/local/bin/setup-sccache

# install build tools
uv pip install build cuda-python numpy setuptools-scm ninja "nvshmem4py-cu${CUDA_MAJOR}"

cd /tmp

# build FlashInfer wheel
uv pip uninstall flashinfer-python || true
git clone https://github.com/flashinfer-ai/flashinfer.git
cd flashinfer
uv pip install -e . --no-build-isolation
uv build --wheel --no-build-isolation --out-dir /wheels
cd ..
rm -rf flashinfer

# build DeepEP wheel
git clone "${DEEPEP_REPO}" deepep
cd deepep
git checkout -q "${DEEPEP_VERSION}"
uv build --wheel --no-build-isolation --out-dir /wheels
cd ..
rm -rf deepep

# build DeepGEMM wheel
git clone "${DEEPGEMM_REPO}" deepgemm
cd deepgemm
git checkout -q "${DEEPGEMM_VERSION}"
git submodule update --init --recursive
uv build --wheel --no-build-isolation --out-dir /wheels
cd ..
rm -rf deepgemm

# build pplx-kernels wheel
git clone "${PPLX_KERNELS_REPO}" pplx-kernels
cd pplx-kernels
NVSHMEM_PREFIX="${NVSHMEM_DIR}" uv build --wheel --out-dir /wheels
cd ..
rm -rf pplx-kernels

if [ "${USE_SCCACHE}" = "true" ]; then
    echo "=== Compiled wheels build complete - sccache stats ==="
    sccache --show-stats
fi
