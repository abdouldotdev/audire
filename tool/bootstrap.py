#!/usr/bin/env python3
"""Generate official Flutter platform shells, then apply Lisiere's native setup.

Never overwrites lib/, assets/, pubspec.yaml or existing native directories.
Requires Flutter on PATH. Run from any directory: python3 tool/bootstrap.py
"""
from __future__ import annotations
import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = "http://schemas.android.com/apk/res/android"
TOOLS = "http://schemas.android.com/tools"
ET.register_namespace("android", ANDROID)
ET.register_namespace("tools", TOOLS)


def tag(name: str) -> str:
    return f"{{{ANDROID}}}{name}"


def patch_android(root: Path) -> None:
    manifest_path = root / "android/app/src/main/AndroidManifest.xml"
    tree = ET.parse(manifest_path)
    manifest = tree.getroot()
    for permission in ["INTERNET", "WAKE_LOCK", "FOREGROUND_SERVICE", "FOREGROUND_SERVICE_MEDIA_PLAYBACK"]:
        name = f"android.permission.{permission}"
        if not any(e.get(tag("name")) == name for e in manifest.findall("uses-permission")):
            ET.SubElement(manifest, "uses-permission", {tag("name"): name})
    app = manifest.find("application")
    if app is None:
        raise ValueError("Flutter's Android manifest has no application element")
    app.set(tag("label"), "Lisière")
    app.set(tag("allowBackup"), "false")
    app.set(tag("usesCleartextTraffic"), "false")
    service_name = "com.ryanheise.audioservice.AudioService"
    if not any(e.get(tag("name")) == service_name for e in app.findall("service")):
        service = ET.SubElement(app, "service", {tag("name"): service_name,
            tag("foregroundServiceType"): "mediaPlayback", tag("exported"): "true",
            f"{{{TOOLS}}}ignore": "Instantiatable"})
        intent = ET.SubElement(service, "intent-filter")
        ET.SubElement(intent, "action", {tag("name"): "android.media.browse.MediaBrowserService"})
    receiver_name = "com.ryanheise.audioservice.MediaButtonReceiver"
    if not any(e.get(tag("name")) == receiver_name for e in app.findall("receiver")):
        receiver = ET.SubElement(app, "receiver", {tag("name"): receiver_name,
            tag("exported"): "true", f"{{{TOOLS}}}ignore": "Instantiatable"})
        intent = ET.SubElement(receiver, "intent-filter")
        ET.SubElement(intent, "action", {tag("name"): "android.intent.action.MEDIA_BUTTON"})
    queries = manifest.find("queries")
    if queries is None:
        queries = ET.SubElement(manifest, "queries")
    if not any(e.get(tag("name")) == "android.intent.action.TTS_SERVICE" for e in queries.iter("action")):
        intent = ET.SubElement(queries, "intent")
        ET.SubElement(intent, "action", {tag("name"): "android.intent.action.TTS_SERVICE"})
    ET.indent(tree, "    ")
    tree.write(manifest_path, encoding="utf-8", xml_declaration=True)

    activity_paths = list((root / "android/app/src/main").rglob("MainActivity.kt"))
    if not activity_paths:
        raise ValueError("No Kotlin MainActivity found. Create with --android-language kotlin.")
    for file in activity_paths:
        source = file.read_text()
        source = source.replace("import io.flutter.embedding.android.FlutterActivity",
            "import com.ryanheise.audioservice.AudioServiceActivity")
        source = source.replace(": FlutterActivity()", ": AudioServiceActivity()")
        file.write_text(source)
    gradle = root / "android/app/build.gradle.kts"
    if not gradle.exists():
        raise ValueError("This bootstrap expects Flutter's Kotlin Gradle template. Use a current stable Flutter SDK.")
    source = gradle.read_text()
    source = re.sub(r"minSdk\s*=\s*(?:flutter\.minSdkVersion|\d+)", "minSdk = 26", source)
    if "lisiere-proguard.pro" not in source:
        source += '\nandroid { buildTypes { getByName("release") { proguardFiles("lisiere-proguard.pro") } } }\n'
    gradle.write_text(source)
    (root / "android/app/lisiere-proguard.pro").write_text("-keep class ai.onnxruntime.** { *; }\n")


def patch_ios(root: Path) -> None:
    plist = root / "ios/Runner/Info.plist"
    with plist.open("rb") as f:
        info = plistlib.load(f)
    info["CFBundleDisplayName"] = "Lisière"
    info["UIBackgroundModes"] = sorted(set(info.get("UIBackgroundModes", []) + ["audio"]))
    # No NSMicrophoneUsageDescription: the app never records the microphone.
    with plist.open("wb") as f:
        plistlib.dump(info, f, sort_keys=False)
    project = root / "ios/Runner.xcodeproj/project.pbxproj"
    source = re.sub(r"IPHONEOS_DEPLOYMENT_TARGET = [0-9.]+;", "IPHONEOS_DEPLOYMENT_TARGET = 16.0;", project.read_text())
    project.write_text(source)
    framework = root / "ios/Flutter/AppFrameworkInfo.plist"
    if framework.exists():
        with framework.open("rb") as f:
            values = plistlib.load(f)
        values["MinimumOSVersion"] = "16.0"
        with framework.open("wb") as f:
            plistlib.dump(values, f, sort_keys=False)
    podfile = root / "ios/Podfile"
    if not podfile.exists():
        podfile.write_text(PODFILE)
    else:
        source = podfile.read_text()
        if re.search(r"(?m)^\s*#?\s*platform :ios,", source):
            source = re.sub(r"(?m)^\s*#?\s*platform :ios,.*$", "platform :ios, '16.0'", source)
        else:
            source = "platform :ios, '16.0'\n" + source
        source = re.sub(r"(?m)^\s*use_frameworks!.*$", "  use_frameworks! :linkage => :static", source)
        podfile.write_text(source)


PODFILE = r'''platform :ios, '16.0'
ENV['COCOAPODS_DISABLE_STATS'] = 'true'
project 'Runner', { 'Debug' => :debug, 'Profile' => :release, 'Release' => :release }
def flutter_root
  generated = File.expand_path(File.join('..', 'Flutter', 'Generated.xcconfig'), __FILE__)
  raise "Run flutter pub get first" unless File.exist?(generated)
  File.foreach(generated) do |line|
    matches = line.match(/FLUTTER_ROOT\=(.*)/)
    return matches[1].strip if matches
  end
  raise "FLUTTER_ROOT not found"
end
require File.expand_path(File.join('packages', 'flutter_tools', 'bin', 'podhelper'), flutter_root)
flutter_ios_podfile_setup
target 'Runner' do
  use_frameworks! :linkage => :static
  flutter_install_all_ios_pods File.dirname(File.realpath(__FILE__))
  target 'RunnerTests' do
    inherit! :search_paths
  end
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end
'''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--patch-only", action="store_true", help="Patch existing shells without invoking Flutter")
    args = parser.parse_args()
    if not args.patch_only:
        flutter = shutil.which("flutter")
        if not flutter:
            parser.error("Flutter n’est pas sur PATH. Installez Flutter stable, puis relancez ce script.")
        missing = [name for name in ("android", "ios") if not (ROOT / name).exists()]
        if missing:
            with tempfile.TemporaryDirectory(prefix="lisiere-flutter-") as temporary:
                generated = Path(temporary) / "lisiere"
                subprocess.run([flutter, "create", "--project-name", "lisiere", "--org", "app.lisiere",
                    "--platforms", "android,ios", "--android-language", "kotlin", "--no-pub", str(generated)], check=True)
                for name in missing:
                    shutil.copytree(generated / name, ROOT / name)
                # Flutter uses .metadata to recognize managed platform migrations.
                metadata = generated / ".metadata"
                if metadata.exists() and not (ROOT / ".metadata").exists():
                    shutil.copy2(metadata, ROOT / ".metadata")
    patch_android(ROOT)
    patch_ios(ROOT)
    print("Plateformes configurées. Exécutez flutter pub get, flutter analyze, flutter test puis flutter run.")
    return 0

if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Configuration interrompue : {error}", file=sys.stderr)
        raise SystemExit(1)
