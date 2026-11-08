import os
from pathlib import Path

home = Path.home()
settings = home / ".config/godot/editor_settings-4.7.tres"
settings.parent.mkdir(parents=True, exist_ok=True)
values = [
    '[gd_resource type="EditorSettings" format=3]',
    '',
    '[resource]',
    f'export/android/android_sdk_path = "{os.environ["ANDROID_HOME"]}"',
    f'export/android/java_sdk_path = "{os.environ["JAVA_HOME"]}"',
    f'export/android/debug_keystore = "{home}/.android/debug.keystore"',
    'export/android/debug_keystore_user = "androiddebugkey"',
    'export/android/debug_keystore_pass = "android"',
]
settings.write_text("\n".join(values) + "\n")
