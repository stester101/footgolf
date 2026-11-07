#!/usr/bin/env bash
# Download the pinned Godot editor (and optionally Android export templates), verifying
# SHA-512 against the official SHA512-SUMS.txt values pinned below.
# Usage: tools/scripts/install_godot.sh <install_dir> [--templates]
set -euo pipefail

GODOT_VERSION="4.7"
GODOT_RELEASE="stable"
EDITOR_ZIP="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64.zip"
EDITOR_BIN="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_linux.x86_64"
TEMPLATES_TPZ="Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_export_templates.tpz"
EDITOR_SHA512="b639ca9c1ddea39bb3df89bd5283a51ca6047467abe6b25e9436566f2b2082ede633025073989ecf39c7d5d3c2493d80ea13e3af6dd5e261bbf89e462d6d2214"
TEMPLATES_SHA512="1035dfde4edcc2472bb0c0b9610ce3ee9302642c2b9957e9066372f9f6bb759ab250c8887551a66f0bc5f51bbd9a58bb45e33a0f29844e97615a9b1138c1120e"
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}"

DIR="${1:?install dir required}"
WANT_TEMPLATES="${2:-}"
mkdir -p "$DIR"
cd "$DIR"

if [ ! -x "$EDITOR_BIN" ]; then
  [ -f "$EDITOR_ZIP" ] || curl -fsSL --retry 4 -o "$EDITOR_ZIP" "$BASE_URL/$EDITOR_ZIP"
  echo "$EDITOR_SHA512  $EDITOR_ZIP" | sha512sum -c -
  unzip -o -q "$EDITOR_ZIP"
  chmod +x "$EDITOR_BIN"
fi
ln -sf "$DIR/$EDITOR_BIN" "$DIR/godot"
"$DIR/godot" --headless --version

if [ "$WANT_TEMPLATES" = "--templates" ]; then
  TPL_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.${GODOT_RELEASE}"
  if [ ! -f "$TPL_DIR/android_debug.apk" ]; then
    [ -f "$TEMPLATES_TPZ" ] || curl -fsSL --retry 4 -o "$TEMPLATES_TPZ" "$BASE_URL/$TEMPLATES_TPZ"
    echo "$TEMPLATES_SHA512  $TEMPLATES_TPZ" | sha512sum -c -
    mkdir -p "$TPL_DIR"
    TMP="$(mktemp -d)"
    unzip -q "$TEMPLATES_TPZ" "templates/android_*" "templates/version.txt" -d "$TMP"
    cp "$TMP"/templates/* "$TPL_DIR/"
    rm -rf "$TMP"
  fi
  cat "$TPL_DIR/version.txt"; echo
  ls -la "$TPL_DIR"
fi
