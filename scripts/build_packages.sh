#!/usr/bin/env bash
# =============================================================================
# kwella — Lambda & Shared Layer Build and Packaging Script
# =============================================================================
set -euo pipefail

# Path setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${PROJECT_ROOT}/kwella-backend"
BUILD_DIR="${BACKEND_DIR}/build"
LAYER_PYTHON_DIR="${BUILD_DIR}/python"
DIST_DIR="${PROJECT_ROOT}/dist"

echo "=== Initialising build directories ==="
rm -rf "${BUILD_DIR}"
rm -rf "${DIST_DIR}"
mkdir -p "${LAYER_PYTHON_DIR}"
mkdir -p "${DIST_DIR}"

# 1. Package Shared Layer
echo "=== Packaging shared Lambda Layer ==="
# Copy local shared module source code to the layer build dir
cp -r "${BACKEND_DIR}/src/layers/kwella_shared/python/." "${LAYER_PYTHON_DIR}/"

# Install target dependencies (Linux, Python 3.12, x86_64 compatible)
echo "=== Downloading and installing Linux-compatible Pydantic dependency ==="
"${PROJECT_ROOT}/.venv/bin/pip" install \
  --platform manylinux2014_x86_64 \
  --target "${LAYER_PYTHON_DIR}" \
  --implementation cp \
  --python-version 3.12 \
  --only-binary=:all: \
  --upgrade \
  pydantic==2.7.4

# Create the shared layer zip
echo "=== Creating kwella_shared_layer.zip ==="
cd "${BUILD_DIR}"
zip -r kwella_shared_layer.zip python/ > /dev/null
cd "${PROJECT_ROOT}"

# 2. Package Lambda Functions
echo "=== Packaging Lambda Functions ==="
for lambda_dir in "${BACKEND_DIR}/src/lambdas"/*; do
  if [ -d "${lambda_dir}" ] && [ -f "${lambda_dir}/handler.py" ]; then
    lambda_name=$(basename "${lambda_dir}")
    echo "  - Packaging ${lambda_name}..."
    cd "${lambda_dir}"
    zip -r "${DIST_DIR}/${lambda_name}.zip" . -x "**/__pycache__/*" > /dev/null
  fi
done

cd "${PROJECT_ROOT}"
echo "=== Packaging complete! ==="
