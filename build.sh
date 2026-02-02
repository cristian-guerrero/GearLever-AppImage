#!/bin/bash
set -e

# 1. Configuration
REPO="mijorus/gearlever"
APP_NAME="GearLever"
APP_DIR="GearLever.AppDir"

# Fetch latest version from GitHub
RELEASES_URL="https://api.github.com/repos/$REPO/releases/latest"
VERSION=$(curl -s "$RELEASES_URL" | jq -r '.tag_name')
DOWNLOAD_URL=$(curl -s "$RELEASES_URL" | jq -r '.tarball_url')

echo "Building $APP_NAME version $VERSION..."

# 2. Preparation
mkdir -p build
cd build
wget -q --show-progress "$DOWNLOAD_URL" -O gearlever.tar.gz
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
export PYTHONPATH="\${HERE}/usr/share/gearlever:\${PYTHONPATH}"

# If run with --integrate-self, it tries to integrate itself
if [ "\$1" = "--integrate-self" ] && [ -n "\$APPIMAGE" ]; then
   exec "\${HERE}/usr/bin/gearlever" --integrate "\$APPIMAGE"
   exit 0
fi

exec "\${HERE}/usr/bin/gearlever" "\$@"
EOF
chmod +x "$APP_DIR/AppRun"

cp "$APP_DIR/usr/share/applications/"*.desktop "$APP_DIR/gearlever.desktop"
cp "$APP_DIR/usr/share/icons/hicolor/512x512/apps/"*.png "$APP_DIR/gearlever.png" || true
sed -i 's/Icon=.*/Icon=gearlever/' "$APP_DIR/gearlever.desktop"

# 6. Build the AppImage
# We use appimagetool to finish the job
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
