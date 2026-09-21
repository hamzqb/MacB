#!/bin/bash
# Copies the parts of llama.cpp MacB builds into Vendor/, from a checkout.
#
#   git clone --depth 1 --branch v0.4.1 https://github.com/ggml-org/llama.cpp.git /tmp/llama
#   bash scripts/vendor-llama.sh /tmp/llama
#
# Only what a Mac with Metal needs: the llama library, ggml's core, its CPU
# backend for Apple silicon and its Metal backend. The Metal kernels are not
# compiled here — this Mac has no Metal compiler without Xcode — but copied as
# source into Vendor/llama-metal, which build.sh puts into the app; ggml
# compiles them on the GPU driver the first time a model loads.
set -euo pipefail

SOURCE="${1:?path to a llama.cpp checkout}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/llama"
METAL="$ROOT/Vendor/llama-metal"
TAG="$(git -C "$SOURCE" describe --tags --always)"
COMMIT="$(git -C "$SOURCE" rev-parse --short HEAD)"

rm -rf "$DEST" "$METAL"
mkdir -p "$DEST/include" "$DEST/include-cpp" "$DEST/src" "$DEST/ggml" "$METAL/kernels"

# Public C headers: what Swift imports. The C++ ones stay out of the module.
cp "$SOURCE/include/llama.h" "$DEST/include/"
for header in ggml.h ggml-alloc.h ggml-backend.h ggml-cpu.h ggml-metal.h ggml-opt.h gguf.h; do
    cp "$SOURCE/ggml/include/$header" "$DEST/include/"
done
cp "$SOURCE/ggml/include/ggml-cpp.h" "$SOURCE/include/llama-cpp.h" "$DEST/include-cpp/"

# llama
rsync -a --exclude CMakeLists.txt --exclude '*.in' "$SOURCE/src/" "$DEST/src/"
printf '#pragma once\n\n#define LLAMA_VERSION "%s"\n#define LLAMA_COMMIT  "%s"\n' "$TAG" "$COMMIT" > "$DEST/src/llama-version.h"

# ggml core
mkdir -p "$DEST/ggml/src"
for file in ggml.c ggml.cpp ggml-alloc.c ggml-backend.cpp ggml-backend-reg.cpp ggml-backend-meta.cpp \
            ggml-opt.cpp ggml-quants.c ggml-threading.cpp gguf.cpp ggml-backend-dl.cpp ggml-backend-dl.h \
            ggml-backend-impl.h ggml-common.h ggml-impl.h ggml-quants.h ggml-threading.h ggml-feats.h; do
    cp "$SOURCE/ggml/src/$file" "$DEST/ggml/src/"
done
printf '#pragma once\n\n#define GGML_VERSION "%s"\n#define GGML_COMMIT  "%s"\n' "$TAG" "$COMMIT" > "$DEST/ggml/src/ggml-version.h"

# CPU backend, Apple silicon only
rsync -a --exclude CMakeLists.txt --exclude cmake --exclude kleidiai --exclude spacemit \
      --exclude 'arch/x86' --exclude 'arch/loongarch' --exclude 'arch/powerpc' --exclude 'arch/riscv' \
      --exclude 'arch/s390' --exclude 'arch/wasm' \
      "$SOURCE/ggml/src/ggml-cpu/" "$DEST/ggml/src/ggml-cpu/"

# Metal backend, without its kernels
rsync -a --exclude CMakeLists.txt --exclude kernels "$SOURCE/ggml/src/ggml-metal/" "$DEST/ggml/src/ggml-metal/"

# Metal kernels as source, laid out the way ggml searches for includes:
# kernels/, then the folder above it, then the one above that.
cp "$SOURCE"/ggml/src/ggml-metal/kernels/* "$METAL/kernels/"
cp "$SOURCE/ggml/src/ggml-metal/ggml-metal-impl.h" "$SOURCE/ggml/src/ggml-common.h" "$METAL/"

cp "$SOURCE/LICENSE" "$DEST/LICENSE"
echo "$TAG ($COMMIT)" > "$DEST/VERSION"
echo "vendored llama.cpp $TAG ($COMMIT)"
