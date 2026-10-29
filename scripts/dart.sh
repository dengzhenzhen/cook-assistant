#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${COOK_FLUTTER_SDK:-$PROJECT_ROOT/.tools/flutter}"
export LD_LIBRARY_PATH="$PROJECT_ROOT/.tools/native/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PUB_CACHE="$PROJECT_ROOT/.tools/pub-cache"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
export FLUTTER_ROOT="$SDK_ROOT"
exec "$SDK_ROOT/bin/cache/dart-sdk/bin/dart" "$@"
