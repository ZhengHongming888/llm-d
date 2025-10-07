#!/bin/bash
# sets up sccache environment variables and starts the server
# expects USE_SCCACHE env var to be set

if [ "${USE_SCCACHE}" = "true" ]; then
    # set up AWS credentials if secrets are available
    if [ -f "/run/secrets/aws_access_key_id" ] && [ -f "/run/secrets/aws_secret_access_key" ]; then
        AWS_ACCESS_KEY_ID="$(cat /run/secrets/aws_access_key_id)"
        export AWS_ACCESS_KEY_ID
        AWS_SECRET_ACCESS_KEY="$(cat /run/secrets/aws_secret_access_key)"
        export AWS_SECRET_ACCESS_KEY
        export AWS_DEFAULT_REGION="us-west-2"
    fi

    export CMAKE_C_COMPILER_LAUNCHER=sccache
    export CMAKE_CXX_COMPILER_LAUNCHER=sccache
    export CMAKE_CUDA_COMPILER_LAUNCHER=sccache

    # configure sccache via environment variables
    export SCCACHE_BUCKET="vllm-nightly-sccache"
    export SCCACHE_REGION="us-west-2"
    export SCCACHE_S3_KEY_PREFIX="llm-d-cache/"
    export SCCACHE_IDLE_TIMEOUT=0

    if ! /usr/local/bin/sccache --start-server; then
        echo "Warning: sccache failed to start, continuing without cache" >&2
        unset CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER CMAKE_CUDA_COMPILER_LAUNCHER
        return 1
    fi

    if ! /usr/local/bin/sccache --show-stats >/dev/null 2>&1; then
        echo "Warning: sccache not responding properly, disabling cache" >&2
        /usr/local/bin/sccache --stop-server 2>/dev/null || true
        unset CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER CMAKE_CUDA_COMPILER_LAUNCHER
        return 1
    fi

    echo "sccache successfully configured with cache prefix: ${SCCACHE_S3_KEY_PREFIX}"
fi
