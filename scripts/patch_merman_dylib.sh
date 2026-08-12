#!/usr/bin/env bash
# merman 0.7.0 ships its macOS dylib with the publisher's CI path as the
# install name — /Users/runner/work/merman/... — instead of @rpath. dyld then
# looks for a path that exists on nobody's machine and the app dies at launch.
#
# Rewrites it to @rpath. Idempotent, and re-run before every macOS build
# because `flutter pub get` can restore the original file.
#
# Reported upstream; delete this once a fixed release lands.
set -euo pipefail

lib=$(ls -d "$HOME"/.pub-cache/hosted/pub.dev/merman-*/macos/Libraries/libmerman_ffi.dylib 2>/dev/null | head -1)
[ -n "${lib:-}" ] || { echo "merman dylib not found — nothing to patch"; exit 0; }

current=$(otool -D "$lib" | sed -n '2p')
if [ "$current" = "@rpath/libmerman_ffi.dylib" ]; then
  echo "merman dylib install name already @rpath"
  exit 0
fi

install_name_tool -id "@rpath/libmerman_ffi.dylib" "$lib"
codesign --force --sign - "$lib" 2>/dev/null || true
echo "patched: $current -> @rpath/libmerman_ffi.dylib"
