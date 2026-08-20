#!/usr/bin/env python3
"""Genera y ajusta la plataforma Android para Codemagic.

El script parte de la plantilla oficial de la versión de Flutter fijada en
codemagic.yaml. Luego aplica únicamente los requisitos Android documentados por
speech_to_text y flutter_local_notifications.
"""

from __future__ import annotations

from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
NATIVE = ROOT / "android_native"


def run(*args: str) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


def _replace_or_fail(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise RuntimeError(f"No pude actualizar {label}. La plantilla Flutter cambió.")
    return updated


def patch_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    permissions = [
        '<uses-permission android:name="android.permission.RECORD_AUDIO" />',
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
        '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
        '<uses-permission android:name="android.permission.VIBRATE" />',
        '<uses-permission android:name="android.permission.WAKE_LOCK" />',
        '<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />',
        '<uses-permission android:name="android.permission.USE_FULL_SCREEN_INTENT" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
        '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />',
    ]

    manifest_close = text.find(">")
    if manifest_close < 0:
        raise RuntimeError("AndroidManifest.xml no tiene una etiqueta <manifest> válida.")

    insertion = ""
    for permission in permissions:
        if permission not in text:
            insertion += f"\n    {permission}"

    if insertion:
        text = text[: manifest_close + 1] + insertion + text[manifest_close + 1 :]

    if "android.speech.RecognitionService" not in text:
        application_pos = text.find("<application")
        if application_pos < 0:
            raise RuntimeError("AndroidManifest.xml no contiene <application>.")
        queries = """\
    <queries>
        <intent>
            <action android:name="android.speech.RecognitionService" />
        </intent>
    </queries>

"""
        text = text[:application_pos] + queries + text[application_pos:]


    text = re.sub(
        r'android:label="[^"]*"',
        'android:label="Mi Agenda IA"',
        text,
        count=1,
    )


    native_components = """
        <receiver android:name=".AlarmReceiver" android:exported="false" />
        <receiver android:name=".AlarmActionReceiver" android:exported="false" />
        <activity
            android:name=".AlarmActivity"
            android:exported="false"
            android:excludeFromRecents="true"
            android:launchMode="singleTop"
            android:showWhenLocked="true"
            android:turnScreenOn="true"
            android:theme="@style/LaunchTheme" />
        <service android:name=".AlarmService" android:exported="false" android:stopWithTask="false" android:foregroundServiceType="mediaPlayback" />
"""
    if ".AlarmService" not in text:
        text = text.replace("</application>", native_components + "    </application>", 1)
    text = text.replace('<activity\n', '<activity\n            android:showWhenLocked="true"\n            android:turnScreenOn="true"\n', 1)
    path.write_text(text, encoding="utf-8")


def patch_app_gradle_kts(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    text = _replace_or_fail(
        text,
        r"^\s*compileSdk\s*=\s*.+$",
        "    compileSdk = 36",
        "compileSdk",
    )
    text = _replace_or_fail(
        text,
        r"^\s*minSdk\s*=\s*.+$",
        "        minSdk = 24",
        "minSdk",
    )

    if "isCoreLibraryDesugaringEnabled = true" not in text:
        text = text.replace(
            "compileOptions {",
            "compileOptions {\n        isCoreLibraryDesugaringEnabled = true",
            1,
        )

    text = re.sub(
        r"sourceCompatibility\s*=\s*JavaVersion\.[A-Z0-9_]+",
        "sourceCompatibility = JavaVersion.VERSION_17",
        text,
        count=1,
    )
    text = re.sub(
        r"targetCompatibility\s*=\s*JavaVersion\.[A-Z0-9_]+",
        "targetCompatibility = JavaVersion.VERSION_17",
        text,
        count=1,
    )

    default_match = re.search(r"defaultConfig\s*\{", text)
    if default_match is None:
        raise RuntimeError("No encontré defaultConfig en build.gradle.kts.")

    block_preview = text[default_match.end() : default_match.end() + 1800]
    if "multiDexEnabled" not in block_preview:
        pos = default_match.end()
        text = text[:pos] + "\n        multiDexEnabled = true" + text[pos:]

    dependency = (
        'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
    )
    if dependency not in text:
        text += f"\n\ndependencies {{\n    {dependency}\n}}\n"

    path.write_text(text, encoding="utf-8")


def patch_app_gradle_groovy(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    text = _replace_or_fail(
        text,
        r"^\s*compileSdk(?:Version)?\s+.+$",
        "    compileSdk 36",
        "compileSdk",
    )
    text = _replace_or_fail(
        text,
        r"^\s*minSdk(?:Version)?\s+.+$",
        "        minSdk 24",
        "minSdk",
    )

    if "coreLibraryDesugaringEnabled true" not in text:
        text = text.replace(
            "compileOptions {",
            "compileOptions {\n        coreLibraryDesugaringEnabled true",
            1,
        )

    text = re.sub(
        r"sourceCompatibility\s+JavaVersion\.[A-Z0-9_]+",
        "sourceCompatibility JavaVersion.VERSION_17",
        text,
        count=1,
    )
    text = re.sub(
        r"targetCompatibility\s+JavaVersion\.[A-Z0-9_]+",
        "targetCompatibility JavaVersion.VERSION_17",
        text,
        count=1,
    )

    default_match = re.search(r"defaultConfig\s*\{", text)
    if default_match is None:
        raise RuntimeError("No encontré defaultConfig en build.gradle.")

    block_preview = text[default_match.end() : default_match.end() + 1800]
    if "multiDexEnabled" not in block_preview:
        pos = default_match.end()
        text = text[:pos] + "\n        multiDexEnabled true" + text[pos:]

    dependency = (
        "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
    )
    if dependency not in text:
        text += f"\n\ndependencies {{\n    {dependency}\n}}\n"

    path.write_text(text, encoding="utf-8")


def patch_agp_version(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    patterns = [
        (
            r'(id\("com\.android\.application"\)\s+version\s+")([^"]+)(")',
            r"\g<1>8.12.1\g<3>",
        ),
        (
            r"(id\s+'com\.android\.application'\s+version\s+')([^']+)(')",
            r"\g<1>8.12.1\g<3>",
        ),
    ]

    for pattern, replacement in patterns:
        updated, count = re.subn(pattern, replacement, text, count=1)
        if count:
            path.write_text(updated, encoding="utf-8")
            return

    # Si Flutter usa otra forma de declarar AGP, no inventamos una estructura:
    # detenemos el build con un mensaje claro.
    raise RuntimeError(
        f"No pude localizar la versión de AGP en {path.name}. "
        "La plantilla Flutter cambió."
    )


def patch_gradle_wrapper(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"gradle-([0-9.]+)-(all|bin)\.zip",
        r"gradle-8.13-bin.zip",
        text,
        count=1,
    )
    if count != 1:
        raise RuntimeError("No pude actualizar Gradle wrapper.")
    path.write_text(updated, encoding="utf-8")



def copy_native_android_files() -> None:
    package_dir = ANDROID / "app" / "src" / "main" / "kotlin" / "com" / "miagendaia" / "mi_agenda_ia"
    package_dir.mkdir(parents=True, exist_ok=True)
    for source in (NATIVE / "kotlin").glob("*.kt"):
        shutil.copy2(source, package_dir / source.name)
    raw_dir = ANDROID / "app" / "src" / "main" / "res" / "raw"
    raw_dir.mkdir(parents=True, exist_ok=True)
    for source in (NATIVE / "res" / "raw").glob("*"):
        shutil.copy2(source, raw_dir / source.name)

def main() -> None:
    run(
        "flutter",
        "create",
        "--no-pub",
        "--platforms=android",
        "--org",
        "com.miagendaia",
        "--project-name",
        "mi_agenda_ia",
        ".",
    )

    # flutter create puede añadir el test de plantilla que referencia `MyApp`.
    # Nuestra aplicación usa `MiAgendaIAApp`, por lo que eliminamos únicamente
    # ese archivo generado por Flutter antes de analizar/probar el proyecto.
    generated_widget_test = ROOT / "test" / "widget_test.dart"
    if generated_widget_test.exists():
        generated_widget_test.unlink()
        print("Eliminado test/widget_test.dart generado por Flutter.", flush=True)

    copy_native_android_files()

    manifest = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    if not manifest.exists():
        raise RuntimeError("Flutter no generó AndroidManifest.xml.")
    patch_manifest(manifest)

    app_kts = ANDROID / "app" / "build.gradle.kts"
    app_groovy = ANDROID / "app" / "build.gradle"
    if app_kts.exists():
        patch_app_gradle_kts(app_kts)
    elif app_groovy.exists():
        patch_app_gradle_groovy(app_groovy)
    else:
        raise RuntimeError("No encontré build.gradle(.kts) de Android.")

    settings_kts = ANDROID / "settings.gradle.kts"
    settings_groovy = ANDROID / "settings.gradle"
    if settings_kts.exists():
        patch_agp_version(settings_kts)
    elif settings_groovy.exists():
        patch_agp_version(settings_groovy)
    else:
        raise RuntimeError("No encontré settings.gradle(.kts).")

    wrapper = ANDROID / "gradle" / "wrapper" / "gradle-wrapper.properties"
    if not wrapper.exists():
        raise RuntimeError("No encontré gradle-wrapper.properties.")
    patch_gradle_wrapper(wrapper)

    print("Android preparado correctamente.", flush=True)


if __name__ == "__main__":
    main()
