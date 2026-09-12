#!/usr/bin/env python3
"""Offline tests for Python tooling/fixtures, not substitutes for Flutter tests."""
from __future__ import annotations
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import xml.etree.ElementTree as ET
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

def load(name: str):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

bootstrap = load("bootstrap")
exporter = load("export_alignment")
make_demo = load("make_demo")

class ToolingTests(unittest.TestCase):
    def test_demo_structure_and_spine(self):
        with zipfile.ZipFile(ROOT / "assets/demo.epub") as archive:
            self.assertEqual(archive.infolist()[0].filename, "mimetype")
            self.assertEqual(archive.infolist()[0].compress_type, zipfile.ZIP_STORED)
            self.assertEqual(archive.read("mimetype"), b"application/epub+zip")
            opf = ET.fromstring(archive.read("EPUB/package.opf"))
            ns = {"opf": "http://www.idpf.org/2007/opf"}
            self.assertEqual([x.attrib["idref"] for x in opf.findall("opf:spine/opf:itemref", ns)], ["ch1", "ch2", "ch3"])
            self.assertIsNone(archive.testzip())
            for name in archive.namelist():
                if name.endswith(("xml", "xhtml", "opf")):
                    ET.fromstring(archive.read(name))

    def test_demo_regeneration(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.epub"
            make_demo.make_demo(path)
            with zipfile.ZipFile(path) as a, zipfile.ZipFile(ROOT / "assets/demo.epub") as b:
                self.assertEqual(a.namelist(), b.namelist())
                for name in a.namelist():
                    self.assertEqual(a.read(name), b.read(name))

    def test_streamed_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample"
            path.write_bytes(b"Lisiere" * 200000)
            self.assertEqual(exporter.sha256_file(path), hashlib.sha256(path.read_bytes()).hexdigest())

    def test_edit_distance(self):
        self.assertEqual(exporter.edit_distance("BONJOUR", "BONSOIR"), 2)
        self.assertEqual(exporter.edit_distance("", "FR"), 2)
        self.assertEqual(exporter.edit_distance("ÉTÉ", "ÉTÉ"), 0)

    def test_android_patch_idempotence(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / "android/app"
            native = app / "src/main/kotlin/app/lisiere/lisiere"
            native.mkdir(parents=True)
            (native / "MainActivity.kt").write_text("package app.lisiere.lisiere\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity: FlutterActivity()\n")
            manifest = app / "src/main/AndroidManifest.xml"
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="lisiere"><activity android:name=".MainActivity"/></application></manifest>')
            gradle = app / "build.gradle.kts"
            gradle.write_text("android { defaultConfig { minSdk = flutter.minSdkVersion } }\n")
            bootstrap.patch_android(root)
            snapshot = {p: p.read_bytes() for p in app.rglob("*") if p.is_file()}
            bootstrap.patch_android(root)
            self.assertEqual(snapshot, {p: p.read_bytes() for p in app.rglob("*") if p.is_file()})
            tree = ET.parse(manifest).getroot()
            self.assertEqual(tree.find("application").get(bootstrap.tag("allowBackup")), "false")
            self.assertEqual(len(tree.find("application").findall("service")), 1)
            self.assertIn("minSdk = 26", gradle.read_text())
            self.assertIn(": AudioServiceActivity()", (native / "MainActivity.kt").read_text())

    def test_ios_patch_idempotence_and_static_linking(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runner = root / "ios/Runner"
            runner.mkdir(parents=True)
            project = root / "ios/Runner.xcodeproj/project.pbxproj"
            project.parent.mkdir()
            project.write_text("IPHONEOS_DEPLOYMENT_TARGET = 13.0;\n")
            info = runner / "Info.plist"
            with info.open("wb") as f:
                plistlib.dump({"CFBundleDisplayName": "lisiere"}, f)
            podfile = root / "ios/Podfile"
            podfile.write_text("# platform :ios, '13.0'\ntarget 'Runner' do\n  use_frameworks!\nend\n")
            bootstrap.patch_ios(root)
            snapshot = {p: p.read_bytes() for p in (root / "ios").rglob("*") if p.is_file()}
            bootstrap.patch_ios(root)
            self.assertEqual(snapshot, {p: p.read_bytes() for p in (root / "ios").rglob("*") if p.is_file()})
            with info.open("rb") as f:
                data = plistlib.load(f)
            self.assertEqual(data["UIBackgroundModes"], ["audio"])
            self.assertNotIn("NSMicrophoneUsageDescription", data)
            self.assertIn("use_frameworks! :linkage => :static", podfile.read_text())
            self.assertIn("IPHONEOS_DEPLOYMENT_TARGET = 16.0;", project.read_text())

    def test_relative_dart_imports_exist(self):
        import re
        for file in (ROOT / "lib").rglob("*.dart"):
            for dependency in re.findall(r"(?:import|export) '([^']+)'", file.read_text()):
                if dependency.startswith("package:lisiere/"):
                    self.assertTrue((ROOT / "lib" / dependency.removeprefix("package:lisiere/")).is_file(), dependency)
                elif ":" not in dependency:
                    self.assertTrue((file.parent / dependency).resolve().is_file(), dependency)

if __name__ == "__main__":
    unittest.main(verbosity=2)
