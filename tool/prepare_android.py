#!/usr/bin/env python3
"""Genera el host Android con el Flutter instalado en CI y aplica ajustes de Mi Agenda IA."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"


def run(*args: str) -> None:
    print("+", " ".join(args), flush=True)
    subprocess.run(args, cwd=ROOT, check=True)


def patch_manifest(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    permissions = [
        '<uses-permission android:name="android.permission.RECORD_AUDIO" />',
        '<uses-permission android:name="android.permission.INTERNET" />',
        '<uses-permission android:name="android.permission.BLUETOOTH" />',
        '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />',
        '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
        '<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />',
    ]
    missing = [p for p in permissions if p not in text]
    if missing:
        insertion = "\n    " + "\n    ".join(missing) + "\n"
        text = text.replace("<manifest", "<manifest", 1)
        close = text.find(">")
        text = text[: close + 1] + insertion + text[close + 1 :]

    queries = '''\n    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n    </queries>\n'''
    if 'android.speech.RecognitionService' not in text:
        application_pos = text.find("<application")
        text = text[:application_pos] + queries + text[application_pos:]

    receivers = '''\n        <receiver\n            android:exported="false"\n            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />\n        <receiver\n            android:exported="false"\n            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">\n            <intent-filter>\n                <action android:name="android.intent.action.BOOT_COMPLETED" />\n                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />\n                <action android:name="android.intent.action.QUICKBOOT_POWERON" />\n                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />\n            </intent-filter>\n        </receiver>\n'''
    if 'ScheduledNotificationReceiver' not in text:
        text = text.replace("</application>", receivers + "    </application>")

    text = re.sub(r'android:label="[^"]*"', 'android:label="Mi Agenda IA"', text, count=1)
    path.write_text(text, encoding="utf-8")


def patch_gradle_kts(path: Path) -> None:
    text = path.read_text(encoding="utf-8")

    text = re.sub(r'compileSdk\s*=\s*flutter\.compileSdkVersion', 'compileSdk = 36', text)
    text = re.sub(r'compileSdk\s*=\s*\d+', 'compileSdk = 36', text, count=1)

    if "isCoreLibraryDesugaringEnabled" not in text:
        marker = "compileOptions {"
        if marker not in text:
            raise RuntimeError(f"No encontré compileOptions en {path}")
        text = text.replace(marker, marker + "\n        isCoreLibraryDesugaringEnabled = true", 1)

    text = re.sub(r'sourceCompatibility\s*=\s*JavaVersion\.VERSION_\d+',
                  'sourceCompatibility = JavaVersion.VERSION_17', text)
    text = re.sub(r'targetCompatibility\s*=\s*JavaVersion\.VERSION_\d+',
                  'targetCompatibility = JavaVersion.VERSION_17', text)

    default_match = re.search(r'defaultConfig\s*\{', text)
    if not default_match:
        raise RuntimeError(f"No encontré defaultConfig en {path}")
    default_end_search = text[default_match.end():]
    if "multiDexEnabled" not in default_end_search[:1500]:
        pos = default_match.end()
        text = text[:pos] + "\n        multiDexEnabled = true" + text[pos:]

    if 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' not in text:
        dep = '\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
        text += dep

    path.write_text(text, encoding="utf-8")


def patch_gradle_groovy(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'compileSdk(?:Version)?\s+flutter\.compileSdkVersion', 'compileSdk 36', text)
    text = re.sub(r'compileSdk(?:Version)?\s+\d+', 'compileSdk 36', text, count=1)

    if "coreLibraryDesugaringEnabled true" not in text:
        marker = "compileOptions {"
        if marker not in text:
            raise RuntimeError(f"No encontré compileOptions en {path}")
        text = text.replace(marker, marker + "\n        coreLibraryDesugaringEnabled true", 1)

    text = re.sub(r'sourceCompatibility\s+JavaVersion\.VERSION_\d+',
                  'sourceCompatibility JavaVersion.VERSION_17', text)
    text = re.sub(r'targetCompatibility\s+JavaVersion\.VERSION_\d+',
                  'targetCompatibility JavaVersion.VERSION_17', text)

    default_match = re.search(r'defaultConfig\s*\{', text)
    if not default_match:
        raise RuntimeError(f"No encontré defaultConfig en {path}")
    if "multiDexEnabled" not in text[default_match.end():default_match.end()+1500]:
        pos = default_match.end()
        text = text[:pos] + "\n        multiDexEnabled true" + text[pos:]

    if "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'" not in text:
        text += "\n\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"

    path.write_text(text, encoding="utf-8")


def main() -> None:
    if ANDROID.exists():
        shutil.rmtree(ANDROID)

    with tempfile.TemporaryDirectory(prefix="mi_agenda_flutter_") as tmp:
        scaffold = Path(tmp) / "mi_agenda_ia"
        run(
            "flutter", "create",
            "--platforms=android",
            "--org", "com.miagendaia",
            "--project-name", "mi_agenda_ia",
            str(scaffold),
        )
        shutil.copytree(scaffold / "android", ANDROID)

    manifest = ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    patch_manifest(manifest)

    kts = ANDROID / "app" / "build.gradle.kts"
    groovy = ANDROID / "app" / "build.gradle"
    if kts.exists():
        patch_gradle_kts(kts)
    elif groovy.exists():
        patch_gradle_groovy(groovy)
    else:
        raise RuntimeError("No encontré build.gradle(.kts) de Android")

    print("Android preparado correctamente.")


if __name__ == "__main__":
    main()
