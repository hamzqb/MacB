#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"
mkdir -p .build
runner_dir="$(mktemp -d "$project_dir/.build/core-tests.XXXXXX")"
trap 'rm -rf "$runner_dir"' EXIT

xcrun swiftc -swift-version 5 -parse-as-library \
  Sources/MacBCore/*.swift scripts/test-core.swift \
  -o "$runner_dir/core-tests"
"$runner_dir/core-tests"
