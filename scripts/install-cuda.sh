#!/usr/bin/env bash
# Assemble a CUDA 13.4 toolkit into ./cuda-13.4 from NVIDIA's pip wheels and the
# redistributable archives, so a build machine needs no system CUDA and no sudo.
#
# Why not the runfile: --toolkitpath gives a complete tree, but the file name
# carries NVIDIA's internal driver build and is not derivable. The pip wheels are
# versioned properly and are what this was tested with.
#
# The two things the wheels do not give you, which CMake needs:
#   - lib64/ with libcudart.so / libcublas.so (the wheels ship lib/ with only the
#     versioned names, so find_package(CUDAToolkit) reports "missing: CUDA_CUDART")
#   - include/cccl (CMake's CUDA::cudart target names that path in its interface,
#     and a missing one fails the generate step, not the configure step)
set -euo pipefail

PREFIX="${1:-$PWD/cuda-13.4}"
WHEEL_VER="${WHEEL_VER:-13.4.92}"
CCCL_VER="${CCCL_VER:-13.3.4.3.1}"
CCCL_URL="https://developer.download.nvidia.com/compute/cuda/redist/cccl/linux-x86_64/cccl-linux-x86_64-${CCCL_VER}-archive.tar.xz"

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }
command -v pip    >/dev/null || { echo "pip is required" >&2; exit 1; }
command -v curl   >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v tar    >/dev/null || { echo "tar is required" >&2; exit 1; }

VENV="$PREFIX/.venv"
python3 -m venv "$VENV"
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet \
    "nvidia-cuda-nvcc==$WHEEL_VER" nvidia-cuda-runtime nvidia-cublas

# Resolve the toolkit dir through a glob rather than hardcoding python3.X: the
# minor version moves, and a wrong guess fails later as a confusing CMake error.
TK=$(echo "$VENV"/lib/python3.*/site-packages/nvidia/cu13)
[ -d "$TK/bin" ] || { echo "nvcc not found under $VENV (looked in $TK)" >&2; exit 1; }
echo "toolkit dir: $TK"

# cccl, merged into the same include tree
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
curl -fsSL -o "$TMP/cccl.tar.xz" "$CCCL_URL"
tar -xf "$TMP/cccl.tar.xz" -C "$TMP"
cp -r "$TMP"/cccl-linux-x86_64-*/include/cccl "$TK/include/"

# lib64, with real files and the unversioned names as relative symlinks.
# Copying (not linking into lib/) is deliberate: a symlink straight to ../lib/
# breaks at link time with "undefined reference to cublasLt...@libcublasLt.so.13",
# because the SONAME of the copy in lib64/ then points at itself.
mkdir -p "$TK/lib64"
for so in libcudart libcublas libcublasLt; do
    src=$(ls "$TK/lib/$so.so."* 2>/dev/null | head -1) || continue
    # Keep the full versioned name (libcudart.so.13): the SONAME of the file is
    # that name, so a copy called libcudart.so.libcudart never resolves.
    cp -L "$src" "$TK/lib64/$(basename "$src")"
done
( cd "$TK/lib64" && for f in *.so.[0-9]*; do
      [ -e "$f" ] || continue
      base="${f%%.so.*}"
      [ -e "$base.so" ] || ln -s "$f" "$base.so"
  done )
# cublasLt is loaded through libcublas's SONAME, so it must sit beside it
for f in "$TK/lib"/*.so.*; do
    [ -e "$TK/lib64/$(basename "$f")" ] || cp -L "$f" "$TK/lib64/" 2>/dev/null || true
done

"$TK/bin/nvcc" --version
test -e "$TK/lib64/libcudart.so"      || { echo "libcudart.so missing" >&2; exit 1; }
test -d "$TK/include/cccl"            || { echo "include/cccl missing" >&2; exit 1; }
echo "OK: $TK"
