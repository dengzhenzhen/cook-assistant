#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="${COOK_FLUTTER_SDK:-$PROJECT_ROOT/.tools/flutter}"
if [[ ! -x "$SDK_ROOT/bin/flutter" ]]; then
  echo "Flutter SDK not found. Install Flutter 3.47.8 and set COOK_FLUTTER_SDK to its directory." >&2
  exit 1
fi
export LD_LIBRARY_PATH="$PROJECT_ROOT/.tools/native/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PATH="$SDK_ROOT/bin:$PATH"
export GRADLE_USER_HOME="$PROJECT_ROOT/.tools/gradle-home"
export PUB_CACHE="$PROJECT_ROOT/.tools/pub-cache"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.dev}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export FLUTTER_SUPPRESS_ANALYTICS=true
if [[ -x "$PROJECT_ROOT/.tools/chrome/chrome" ]]; then
  export CHROME_EXECUTABLE="$PROJECT_ROOT/.tools/chrome/chrome"
fi
if [[ -d "$PROJECT_ROOT/.tools/jdk-root/usr/lib/jvm/java-17-openjdk-amd64" ]]; then
  export JAVA_HOME="$PROJECT_ROOT/.tools/jdk-root/usr/lib/jvm/java-17-openjdk-amd64"
fi
if [[ -d "$PROJECT_ROOT/.tools/android-sdk" ]]; then
  export ANDROID_HOME="$PROJECT_ROOT/.tools/android-sdk"
fi
exec "$SDK_ROOT/bin/flutter" --no-version-check "$@"
