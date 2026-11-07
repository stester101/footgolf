# Build and install

## Toolchain (pinned)
- Godot **4.7-stable** editor (`Godot_v4.7-stable_linux.x86_64.zip`, SHA-512 `b639ca9c…2214`) and
  matching export templates (`Godot_v4.7-stable_export_templates.tpz`, SHA-512 `1035dfde…120e`).
  `tools/scripts/install_godot.sh` downloads and verifies both.
- Renderer: Mobile (Vulkan), with `rendering_device/fallback_to_opengl3=true` so devices without
  Vulkan fall back to the Compatibility (OpenGL ES 3) renderer.
- Android: standard (non-Gradle) APK export, minSdk 24, targetSdk 36, ABIs arm64-v8a, armeabi-v7a,
  x86_64. Package `com.footballgolf.prototype` (editable engineering default). No permissions.
- CI: JDK 17 (Temurin), Android SDK preinstalled on `ubuntu-24.04` runners + `build-tools;35.0.0`.

## Get the APK from GitHub Actions
1. GitHub → **Actions** → workflow **Android debug APK** → a successful (green) run.
2. **Artifacts** → `football-golf-v0.1-debug-apk` → download the ZIP, extract
   `football-golf-v0.1-debug.apk`.
3. Copy to the phone (or download on the phone), open it, allow "Install unknown apps" for the
   app you opened it with, and install. Run manually with **Run workflow** (workflow_dispatch) too.

### Debug signing
The workflow signs with a **debug** keystore: from the optional repository secret
`ANDROID_DEBUG_KEYSTORE_BASE64` if set, else a keystore cached by Actions, else a freshly
generated one. If the signing key changes between builds, Android refuses the update
("package conflicts"): uninstall the old app first (this deletes saved footballer edits and settings).
For a permanent identity, create a debug keystore once and store it base64-encoded in that secret:
```bash
keytool -genkeypair -keystore debug.keystore -storepass android -alias androiddebugkey \
  -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US"
base64 -w0 debug.keystore   # paste into the secret; never commit the file
```

## Local build (Linux)
```bash
tools/scripts/install_godot.sh ~/godot --templates
export GODOT=~/godot/godot
tools/scripts/run_tests.sh
# editor settings for export (adjust paths):
mkdir -p ~/.config/godot && cat > ~/.config/godot/editor_settings-4.7.tres <<'EOF'
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "/path/to/android-sdk"
export/android/java_sdk_path = "/path/to/jdk-17"
export/android/debug_keystore = "/path/to/debug.keystore"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
mkdir -p builds && $GODOT --headless --path . --export-debug "Android" builds/football-golf-v0.1-debug.apk
tools/scripts/verify_apk.sh builds/football-golf-v0.1-debug.apk
```
The SDK path needs `platform-tools/adb` and `build-tools/<ver>/apksigner`.

## Controls
- **Aim:** drag horizontally on the course (behind-ball view), full 360°.
- **Caps / Goals:** segmented buttons. **Choose footballer:** search by name, filter nationality.
- **TAKE SHOT:** the only way to shoot. **Skip ▸▸** fast-forwards the (deterministic) simulation.
- **Overhead:** tactical top-down map; tap to measure yardage from the ball (not a prediction).
- **Card:** scorecard + revealed shot history. **DEV:** developer panel. **II:** pause.
- Android **Back** closes overlays/dev panel, then opens pause; on the main menu it exits.
