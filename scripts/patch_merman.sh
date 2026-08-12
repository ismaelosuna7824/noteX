#!/usr/bin/env bash
#
# Repairs the merman package in the pub cache so it can be built and loaded.
#
# Two upstream defects, both reported, both trivial to fix at the source:
#
#   macOS — the dylib ships with the publisher's CI path as its install name
#           (/Users/runner/work/merman/...) instead of @rpath, so dyld searches
#           a location that exists on nobody's machine and the app dies at
#           launch.                     https://github.com/Latias94/merman/issues/55
#
#   Linux — the plugin's CMake links `flutter_wrapper_plugin`, a target Flutter
#           defines only on Windows, so the link fails outright.
#                                       https://github.com/Latias94/merman/issues/56
#
# Runs on every platform and only touches what applies, so one call in a build
# script covers all three. Idempotent, and must run AFTER `flutter pub get`,
# which restores the pristine files.
#
# Delete this script, and its callers, once a fixed merman is released.
set -euo pipefail

root=$(ls -d "${PUB_CACHE:-$HOME/.pub-cache}"/hosted/pub.dev/merman-* 2>/dev/null | head -1)
if [ -z "${root:-}" ]; then
  echo "merman not found in the pub cache — nothing to patch"
  exit 0
fi
echo "patching $root"

# ── macOS: install name ─────────────────────────────────────────────────────
dylib="$root/macos/Libraries/libmerman_ffi.dylib"
if [ -f "$dylib" ] && command -v otool >/dev/null 2>&1; then
  current=$(otool -D "$dylib" | sed -n '2p')
  if [ "$current" = "@rpath/libmerman_ffi.dylib" ]; then
    echo "  macOS install name already @rpath"
  else
    install_name_tool -id "@rpath/libmerman_ffi.dylib" "$dylib"
    # Rewriting a Mach-O invalidates its signature; without this the loader
    # rejects the library it can now find.
    codesign --force --sign - "$dylib" 2>/dev/null || true
    echo "  macOS install name: $current -> @rpath/libmerman_ffi.dylib"
  fi
fi

# ── Linux: the Windows-only link target ─────────────────────────────────────
cmake="$root/linux/CMakeLists.txt"
if [ -f "$cmake" ]; then
  if grep -q 'flutter_wrapper_plugin' "$cmake"; then
    # Only the stray target is removed; `flutter` is what a Linux plugin links,
    # exactly as url_launcher_linux, screen_retriever and window_manager do.
    perl -pi -e 's/\bflutter\s+flutter_wrapper_plugin\b/flutter/' "$cmake"
    grep -q 'flutter_wrapper_plugin' "$cmake" &&
      { echo "::error::could not remove flutter_wrapper_plugin from $cmake"; exit 1; }
    echo "  Linux CMake: dropped flutter_wrapper_plugin"
  else
    echo "  Linux CMake already clean"
  fi
fi

echo "done"
