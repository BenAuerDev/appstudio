#!/usr/bin/env bash
# Builds App Studio for Linux and packs it into an AppImage.
#
# Usage: tool/linux/build_appimage.sh     (or: make appimage)
#
# Writes dist/linux/AppStudio-<version>-x86_64.AppImage, <version> being the
# one in pubspec.yaml (without the build number).
#
# Optional environment:
#   FLUTTER               the flutter to build with (default: flutter on PATH)
#   SKIP_BUILD=1          package the release build that is already there
#   APPIMAGETOOL          path to appimagetool; the pinned release is
#                         downloaded into build/linux/tools if unset
#   APPIMAGE_UPDATE_INFO  update information for AppImageUpdate and Gear Lever,
#                         e.g. "zsync|https://<host>/<path>/AppStudio-latest-x86_64.AppImage.zsync".
#                         With it, appimagetool also writes a .zsync file next
#                         to the AppImage. A release overwrites the .zsync at
#                         that fixed URL. Gear Lever offers an update whenever
#                         the .zsync's SHA-1 differs from the installed
#                         file's; it does not compare versions.
#   APPIMAGE_FILE_URL     where this AppImage will be downloaded from, written
#                         into the .zsync, e.g. "https://<host>/releases/linux/
#                         <version>/b<build>/AppStudio-<version>-x86_64.AppImage".
#                         Unset, the .zsync names the AppImage relative to
#                         itself, so every release would have to sit in the
#                         .zsync's folder; with it, the AppImage keeps a path
#                         of its own that is never overwritten.
#
# The AppImage carries App Studio, Flutter's engine and CEF. GTK 3 and the
# other desktop libraries come from the system; the build needs glibc 2.38 or
# newer at run time (Ubuntu 24.04 and later), so build on the oldest system
# it should run on. The build machine needs Flutter's Linux build tools, plus
# curl, python3, and readelf and strip (binutils).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
flutter="${FLUTTER:-flutter}"
bundle="$root/build/linux/x64/release/bundle"
appdir="$root/build/linux/AppStudio.AppDir"
dist="$root/dist/linux"
app_id="dev.serverpod.appstudio"

full_version="$(sed -n 's/^version: *\([^ ]*\).*/\1/p' "$root/pubspec.yaml")"
version="${full_version%%+*}"
if [[ -z "$version" ]]; then
  echo "No version in pubspec.yaml." >&2
  exit 1
fi
out="$dist/AppStudio-${version}-x86_64.AppImage"

step() { echo "==> $*"; }

missing=()
for cmd in curl python3 readelf sha256sum strip; do
  command -v "$cmd" > /dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
  echo "Missing on this machine: ${missing[*]}" >&2
  exit 1
fi

# --- Build -----------------------------------------------------------------

if [[ "${SKIP_BUILD:-}" != 1 ]]; then
  step "flutter build linux --release"
  # A release build rewrites the generated plugin files (it drops Widgetbook's
  # url_launcher, a dev dependency). They are committed, so put them back
  # whatever happens, as tool/windows/build_release.ps1 does.
  restore_generated() {
    git -C "$root" checkout -- \
      linux/flutter/generated_plugin_registrant.cc \
      linux/flutter/generated_plugins.cmake \
      windows/flutter/generated_plugin_registrant.cc \
      windows/flutter/generated_plugins.cmake
  }
  trap restore_generated EXIT
  (cd "$root" && "$flutter" build linux --release)
  restore_generated
  trap - EXIT
fi

step "Checking the bundle"
# Flutter's own files, then CEF's: libcef.so and what it loads from beside
# itself (resources, locales, ANGLE's GL libraries, SwiftShader's software
# Vulkan).
# libflutter_pty2.so is a native asset (Publish to Cloud's terminal), built by
# the package's hook rather than CMake, so nothing else would notice it gone.
for file in appstudio lib/libapp.so lib/libflutter_linux_gtk.so \
  data/flutter_assets lib/libflutter_pty2.so \
  lib/libwebview_cef_plugin.so lib/libcef.so lib/icudtl.dat \
  lib/resources.pak lib/chrome_100_percent.pak lib/chrome_200_percent.pak \
  lib/v8_context_snapshot.bin lib/locales lib/libEGL.so lib/libGLESv2.so \
  lib/libvk_swiftshader.so lib/vk_swiftshader_icd.json; do
  if [[ ! -e "$bundle/$file" ]]; then
    echo "Missing from the release build: $bundle/$file" >&2
    exit 1
  fi
done

# The bundle records the version it was built with. With SKIP_BUILD it can be
# older than pubspec.yaml, and would then ship under the wrong version.
built="$(python3 -I -c 'import json, sys
v = json.load(open(sys.argv[1]))
print(v["version"] + "+" + v["build_number"])' "$bundle/data/flutter_assets/version.json")"
if [[ "$built" != "$full_version" ]]; then
  echo "The release build is $built, pubspec.yaml says $full_version: build again." >&2
  exit 1
fi

# --- AppDir ----------------------------------------------------------------

step "Assembling $appdir"
rm -rf "$appdir"
# The bundle keeps its layout (appstudio, lib/, data/): the executable finds
# its libraries through its RPATH ($ORIGIN/lib) and CEF finds its resources
# beside libcef.so. CEF's helper processes are this same executable, started
# from inside the mounted image.
mkdir -p "$appdir/usr/lib/appstudio" "$appdir/usr/bin"
cp -a "$bundle"/. "$appdir/usr/lib/appstudio/"
ln -s ../lib/appstudio/appstudio "$appdir/usr/bin/appstudio"

step "Stripping debug symbols"
# libcef.so ships with its symbols: 1.4 GB of a 1.5 GB bundle. Only files
# that still have a symbol table are stripped; the others, Flutter's engine
# among them, ship as they were built. libapp.so (the Dart AOT snapshot) is
# left alone: Flutter already strips it.
while IFS= read -r -d '' file; do
  # Captured, not piped into grep -q: grep stopping at the match would cut
  # readelf off, and pipefail would read that as no symbol table.
  if [[ "$(readelf -S "$file")" == *.symtab* ]]; then
    strip --strip-unneeded "$file"
  fi
done < <(find "$appdir/usr/lib/appstudio" -type f \
  \( -name '*.so' -o -name '*.so.*' -o -name appstudio \) ! -name libapp.so -print0)

step "Icons and desktop entry"
# Linux icons run nearly edge to edge, like Windows' and unlike the macOS
# icon, which sits on Apple's grid with a margin. So they come from the
# Windows .ico, whose frames are PNGs: one source for both.
python3 -I - "$root/windows/runner/resources/app_icon.ico" \
  "$appdir/usr/share/icons/hicolor" "$app_id" <<'PY'
import os, struct, sys
ico, hicolor, name = sys.argv[1:4]
data = open(ico, "rb").read()
count = struct.unpack("<HHH", data[:6])[2]
wanted = {16, 24, 32, 48, 64, 128, 256}
for i in range(count):
    w, _h, _c, _r, _p, _b, size, offset = struct.unpack(
        "<BBBBHHII", data[6 + 16 * i:22 + 16 * i])
    w = w or 256
    frame = data[offset:offset + size]
    if w in wanted and frame[:4] == b"\x89PNG":
        folder = os.path.join(hicolor, f"{w}x{w}", "apps")
        os.makedirs(folder, exist_ok=True)
        open(os.path.join(folder, name + ".png"), "wb").write(frame)
        wanted.discard(w)
if wanted:
    sys.exit(f"{ico} has no PNG frames for {sorted(wanted)}")
PY
cp "$appdir/usr/share/icons/hicolor/256x256/apps/$app_id.png" "$appdir/$app_id.png"
ln -s "$app_id.png" "$appdir/.DirIcon"

# StartupWMClass is the GTK application id the runner sets (APPLICATION_ID in
# linux/CMakeLists.txt): it is how a dock matches the window to this entry.
# X-AppImage-Version is the version AppImage managers such as Gear Lever show.
mkdir -p "$appdir/usr/share/applications"
cat > "$appdir/usr/share/applications/$app_id.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=App Studio
Comment=Build full-stack apps with Flutter and Serverpod
Exec=appstudio
Icon=$app_id
Terminal=false
StartupNotify=true
StartupWMClass=$app_id
Categories=Development;IDE;
X-AppImage-Version=$version
DESKTOP
ln -s "usr/share/applications/$app_id.desktop" "$appdir/$app_id.desktop"

cat > "$appdir/AppRun" <<'APPRUN'
#!/bin/sh
here="$(dirname "$(readlink -f "$0")")"
exec "$here/usr/lib/appstudio/appstudio" "$@"
APPRUN
chmod +x "$appdir/AppRun"

# --- AppImage --------------------------------------------------------------

# appimagetool and the runtime it puts in front of the image are pinned and
# checked against their sha256, as WinSparkle is on Windows. Left to itself,
# appimagetool would also fetch the runtime from the moving "continuous"
# release on every run.
appimagetool_version=1.9.1
appimagetool_sha256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
runtime_version=20251108
runtime_sha256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
tools="$root/build/linux/tools"

# Downloads $1 to $2 unless a file with sha256 $3 is already there.
fetch_pinned() {
  local url="$1" dest="$2" sha="$3"
  if [[ -f "$dest" ]] && echo "$sha  $dest" | sha256sum -c --status; then
    return
  fi
  step "Downloading $url"
  mkdir -p "$(dirname "$dest")"
  curl -fsSL -o "$dest.part" "$url"
  if ! echo "$sha  $dest.part" | sha256sum -c --status; then
    rm -f "$dest.part"
    echo "Checksum mismatch for $url" >&2
    exit 1
  fi
  mv "$dest.part" "$dest"
}

tool="${APPIMAGETOOL:-}"
if [[ -z "$tool" ]]; then
  tool="$tools/appimagetool-$appimagetool_version-x86_64.AppImage"
  fetch_pinned \
    "https://github.com/AppImage/appimagetool/releases/download/$appimagetool_version/appimagetool-x86_64.AppImage" \
    "$tool" "$appimagetool_sha256"
  chmod +x "$tool"
fi
runtime="$tools/runtime-$runtime_version-x86_64"
fetch_pinned \
  "https://github.com/AppImage/type2-runtime/releases/download/$runtime_version/runtime-x86_64" \
  "$runtime" "$runtime_sha256"

update=()
if [[ -n "${APPIMAGE_UPDATE_INFO:-}" ]]; then
  update=(--updateinformation "$APPIMAGE_UPDATE_INFO")
  if [[ -n "${APPIMAGE_FILE_URL:-}" ]]; then
    update+=(--file-url "$APPIMAGE_FILE_URL")
  fi
elif [[ -n "${APPIMAGE_FILE_URL:-}" ]]; then
  echo "APPIMAGE_FILE_URL needs APPIMAGE_UPDATE_INFO: it only goes into the .zsync." >&2
  exit 1
fi

step "Packing $out"
mkdir -p "$dist"
rm -f "$out" "$out.zsync"
# CI runners have no FUSE; extract-and-run works everywhere. appimagetool
# writes the .zsync into the working directory. VERSION is unset because
# appimagetool would write it over the desktop entry's X-AppImage-Version: a
# VERSION left in the caller's environment would ship as App Studio's.
(
  cd "$dist"
  env -u VERSION APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 \
    "$tool" --runtime-file "$runtime" "${update[@]}" "$appdir" "$out"
)
if [[ -n "${APPIMAGE_UPDATE_INFO:-}" && ! -s "$out.zsync" ]]; then
  echo "appimagetool wrote no $out.zsync." >&2
  exit 1
fi

step "Built $out ($(du -h "$out" | cut -f1))"
