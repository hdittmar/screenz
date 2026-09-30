#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
export SCREENZ_PREVIEW_DIR="$PWD/.build/previews"
swift test --build-system native --disable-sandbox --cache-path "$PWD/.build/cache"
