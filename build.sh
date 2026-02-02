#!/bin/bash
set -e

# 1. Configuration
REPO="mijorus/gearlever"
APP_NAME="GearLever"
APP_DIR="GearLever.AppDir"

# Fetch latest version from GitHub
RELEASES_URL="https://api.github.com/repos/$REPO/releases/latest"
# Check if GITHUB_TOKEN is available for authenticated requests
CURL_OPTS=""
if [ ! -z "$GITHUB_TOKEN" ]; then
  CURL_OPTS="-H \"Authorization: token $GITHUB_TOKEN\""
fi

RESPONSE=$(curl -s $CURL_OPTS "$RELEASES_URL")
VERSION=$(echo "$RESPONSE" | jq -r '.tag_name')
DOWNLOAD_URL=$(echo "$RESPONSE" | jq -r '.tarball_url')

if [ "$VERSION" == "null" ] || [ -z "$VERSION" ]; then
  echo "Error: Could not fetch version from API"
  echo "Response: $RESPONSE"
  exit 1
fi

echo "Building $APP_NAME version $VERSION..."

# 2. Preparation
mkdir -p build
cd build
curl -L $CURL_OPTS "$DOWNLOAD_URL" -o gearlever.tar.gz
mkdir -p source
tar -xzf gearlever.tar.gz -C source --strip-components=1

# 3. Build & Install into AppDir
cd source
meson setup _build --prefix=/usr
DESTDIR=../GearLever.AppDir ninja -C _build install
cd ..

# 4. Finalize AppDir
APP_DIR="GearLever.AppDir"
cat <<EOF > "$APP_DIR/AppRun"
#!/bin/sh
HERE="\$(dirname "\$(readlink -f "\${0}")")"

# Portable Python Environment
export PYTHONHOME="\${HERE}/usr"
export PYTHONPATH="\${HERE}/usr/share/gearlever:\${HERE}/usr/lib/python3.12:\${HERE}/usr/lib/python3/dist-packages:\${PYTHONPATH}"

# GTK/GIO Portability
export XDG_DATA_DIRS="\${HERE}/usr/share:\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
export GSETTINGS_SCHEMA_DIR="\${HERE}/usr/share/glib-2.0/schemas"
export GI_TYPELIB_PATH="\${HERE}/usr/lib/x86_64-linux-gnu/girepository-1.0"

# Use the bundled python from sharun
if [ -f "\${HERE}/bin/python3" ]; then
  EXEC="\${HERE}/bin/python3"
else
  EXEC="python3"
fi

# If run with --integrate-self, it tries to integrate itself
if [ "\$1" = "--integrate-self" ] && [ -n "\$APPIMAGE" ]; then
   exec "\$EXEC" "\${HERE}/usr/bin/gearlever" --integrate "\$APPIMAGE"
   exit 0
fi

exec "\$EXEC" "\${HERE}/usr/bin/gearlever" "\$@"
EOF
chmod +x "$APP_DIR/AppRun"

# Full search for icons
ICON_PATH=$(find "$APP_DIR" -name "*gearlever*" -name "*.png" | head -n 1)
if [ -z "$ICON_PATH" ]; then
  ICON_PATH=$(find "$APP_DIR" -name "*.png" | grep -v "appstream" | head -n 1)
fi
if [ -n "$ICON_PATH" ]; then
  cp "$ICON_PATH" "$APP_DIR/gearlever.png"
  mkdir -p "$APP_DIR/usr/share/icons/hicolor/512x512/apps"
  cp "$ICON_PATH" "$APP_DIR/usr/share/icons/hicolor/512x512/apps/gearlever.png"
else
  echo "Error: Icon not found"
  exit 1
fi

cp "$APP_DIR/usr/share/applications/"*.desktop "$APP_DIR/gearlever.desktop"
sed -i 's/Icon=.*/Icon=gearlever/' "$APP_DIR/gearlever.desktop"

# Compile GSettings schemas
if [ -d "$APP_DIR/usr/share/glib-2.0/schemas" ]; then
   echo "Compiling GSettings schemas..."
   glib-compile-schemas "$APP_DIR/usr/share/glib-2.0/schemas"
fi

# 5. Patch hardcoded paths (Meson hardcodes /usr/share/gearlever)
GEARLEVER_BIN="$APP_DIR/usr/bin/gearlever"
if [ -f "$GEARLEVER_BIN" ]; then
  echo "Patching hardcoded paths in $GEARLEVER_BIN"
  sed -i "s|pkgdatadir = '.*'|pkgdatadir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'share', 'gearlever'))|" "$GEARLEVER_BIN"
  sed -i "s|localedir = '.*'|localedir = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'share', 'locale'))|" "$GEARLEVER_BIN"
fi

# 6. Build the AppImage via sharun (for portability)
# We use sharun to bundle dependencies for immutable systems
wget -q https://github.com/VHSgunzo/sharun/releases/download/v0.7.9/sharun-x86_64 -O sharun
chmod +x sharun

# 1. Bundle Python Standard Library and essential site-packages
# sharun bundles binaries, but we need the .py files for Python to function
mkdir -p "$APP_DIR/usr/lib/python3.12"
cp -ra /usr/lib/python3.12/. "$APP_DIR/usr/lib/python3.12/"

# Also the dependencies installed via apt (gi, requests, xdg, dbus, magic)
mkdir -p "$APP_DIR/usr/lib/python3/dist-packages"
cp -ra /usr/lib/python3/dist-packages/. "$APP_DIR/usr/lib/python3/dist-packages/"

# Bundle GObject Introspection typelibs
mkdir -p "$APP_DIR/usr/lib/x86_64-linux-gnu/girepository-1.0"
cp -ra /usr/lib/x86_64-linux-gnu/girepository-1.0/. "$APP_DIR/usr/lib/x86_64-linux-gnu/girepository-1.0/"

# 2. Bundle the python interpreter and its dependencies.
# We also bundle libadwaita/gtk4 as they are loaded via GI (dlopen)
./sharun lib4bin \
  --dst-dir "$APP_DIR" \
  --with-hooks \
  --hard-links \
  --verbose \
  /usr/bin/python3 \
  /usr/lib/x86_64-linux-gnu/libadwaita-1.so.0 \
  /usr/lib/x86_64-linux-gnu/libgtk-4.so.1

# Final AppImage creation
wget -q https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage -O appimagetool
chmod +x appimagetool

export ARCH=x86_64
export APPIMAGE_EXTRACT_AND_RUN=1

REPO_OWNER=$(echo $GITHUB_REPOSITORY | cut -d'/' -f1)
REPO_NAME=$(echo $GITHUB_REPOSITORY | cut -d'/' -f2)

if [ ! -z "$GITHUB_REPOSITORY" ]; then
  UPDATE_INFO="gh-releases-zsync|${REPO_OWNER}|${REPO_NAME}|latest|GearLever-x86_64.AppImage.zsync"
  ./appimagetool -u "$UPDATE_INFO" "$APP_DIR" "GearLever-x86_64.AppImage"
else
  ./appimagetool "$APP_DIR" "GearLever-x86_64.AppImage"
fi

echo "Build complete: build/GearLever-x86_64.AppImage"
