#!/usr/bin/env python3
"""Offline structural/variable checks, not an Xcode build-settings evaluation."""
from pathlib import Path
import hashlib
import json
import plistlib
import re
import unittest
import tempfile

from validate_bundle_products import read_bundle_pair, validate_release_settings

ROOT = Path(__file__).resolve().parents[1]

def uid(key):
    return hashlib.sha256(key.encode()).hexdigest()[:24].upper()

class BundleConfigurationChecks(unittest.TestCase):
    def setUp(self):
        self.project = (ROOT/'WatchCodex.xcodeproj/project.pbxproj').read_text()
        self.watch = plistlib.loads((ROOT/'Watch/Info.plist').read_bytes())
        self.phone = plistlib.loads((ROOT/'iPhone/Info.plist').read_bytes())

    def settings(self, key):
        line = next(line for line in self.project.splitlines() if line.startswith(uid(key)+' = '))
        body = re.search(r'buildSettings = \{ (.*?) \}; name =', line).group(1)
        return {name: json.loads(value) if value.startswith('"') else value
                for name, value in re.findall(r'(\w+) = ("(?:[^"\\]|\\.)*"|[^;]+);', body)}

    def test_single_project_setting_drives_both_targets(self):
        for mode in ['Debug', 'Release']:
            project = self.settings('project'+mode)
            self.assertEqual(project['WATCH_CODEX_PHONE_BUNDLE_ID'], 'org.example.watchcodex')
            for name in ['Phone', 'Watch']:
                target = self.settings(name+mode)
                self.assertNotIn('WATCH_CODEX_PHONE_BUNDLE_ID', target)
                suffix = '.watchkitapp' if name == 'Watch' else ''
                self.assertEqual(target['PRODUCT_BUNDLE_IDENTIFIER'], '$(WATCH_CODEX_PHONE_BUNDLE_ID)'+suffix)
                self.assertEqual(target['CODE_SIGN_STYLE'], 'Automatic')
                self.assertEqual(target['DEVELOPMENT_TEAM'], '')
        self.assertEqual(self.watch['WKCompanionAppBundleIdentifier'], '$(WATCH_CODEX_PHONE_BUNDLE_ID)')
        self.assertTrue(self.watch['WKApplication'])
        self.assertFalse(self.watch['WKRunsIndependentlyOfCompanionApp'])
        self.assertNotIn('com.yihang.watchcodex', self.project)

    def test_synthetic_project_overrides_resolve_companion_pair(self):
        # Model just the $(NAME) substitutions used here. Actual processed plists
        # and xcodebuild -showBuildSettings still need validation on macOS.
        def expand(value, settings):
            for _ in range(4):
                value = re.sub(r'\$\((\w+)\)', lambda m: settings[m.group(1)], value)
            self.assertNotIn('$(', value)
            return value
        for mode in ['Debug', 'Release']:
            for phone_id in ['org.example.watchcodex', 'com.example.personal-remote', 'net.team.qa.watchcodex']:
                with self.subTest(mode=mode, phone_id=phone_id):
                    project = self.settings('project'+mode)
                    project['WATCH_CODEX_PHONE_BUNDLE_ID'] = phone_id
                    phone = {**project, **self.settings('Phone'+mode)}
                    watch = {**project, **self.settings('Watch'+mode)}
                    self.assertEqual(expand(self.phone['CFBundleIdentifier'], phone), phone_id)
                    self.assertEqual(expand(self.watch['CFBundleIdentifier'], watch), phone_id+'.watchkitapp')
                    self.assertEqual(expand(self.watch['WKCompanionAppBundleIdentifier'], watch), phone_id)

    def test_plists_visible_in_navigator_not_copied_as_resources(self):
        group = next(line for line in self.project.splitlines() if line.startswith(uid('main')+' = '))
        for path in ['iPhone/Info.plist', 'Watch/Info.plist']:
            ref = uid(path)
            self.assertIn(ref, group)
            self.assertIn(f'{ref} = {{ isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = "{path}";', self.project)
            self.assertNotRegex(self.project, r'isa = PBXBuildFile; fileRef = '+ref)

class ProcessedBundleChecks(unittest.TestCase):
    def test_processed_pair_and_mismatches(self):
        with tempfile.TemporaryDirectory() as directory:
            phone, watch = Path(directory)/'Phone.app', Path(directory)/'Watch.app'
            phone.mkdir(); watch.mkdir()
            phone_id = 'net.example.watchcodex.validation'
            (phone/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': phone_id}, fmt=plistlib.FMT_BINARY))
            valid = {'CFBundleIdentifier': phone_id+'.watchkitapp', 'WKCompanionAppBundleIdentifier': phone_id}
            (watch/'Info.plist').write_bytes(plistlib.dumps(valid, fmt=plistlib.FMT_BINARY))
            self.assertEqual(read_bundle_pair(phone, watch, phone_id), (phone_id, phone_id+'.watchkitapp'))
            for changed in [
                {'WKCompanionAppBundleIdentifier': 'org.example.watchcodex'},
                {'WKCompanionAppBundleIdentifier': '$(WATCH_CODEX_PHONE_BUNDLE_ID)'},
                {'CFBundleIdentifier': 'org.example.watchcodex.watchkitapp'},
            ]:
                (watch/'Info.plist').write_bytes(plistlib.dumps({**valid, **changed}))
                with self.assertRaises(ValueError):
                    read_bundle_pair(phone, watch, phone_id)
            (watch/'Info.plist').write_bytes(plistlib.dumps(valid))
            with self.assertRaises(ValueError):
                read_bundle_pair(phone, watch, 'net.example.different')

    def test_release_settings_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'settings.json'
            phone_id = 'net.example.watchcodex.validation'
            for target, suffix in [('WatchCodexPhone', ''), ('WatchCodexWatch', '.watchkitapp')]:
                settings = {'CONFIGURATION': 'Release', 'WATCH_CODEX_PHONE_BUNDLE_ID': phone_id,
                            'PRODUCT_BUNDLE_IDENTIFIER': phone_id+suffix}
                path.write_text(json.dumps([{'target': target, 'buildSettings': settings}]))
                validate_release_settings(path, target, phone_id)
                for name in settings:
                    broken = {**settings, name: 'incorrect'}
                    path.write_text(json.dumps([{'target': target, 'buildSettings': broken}]))
                    with self.assertRaises(ValueError):
                        validate_release_settings(path, target, phone_id)
                path.write_text('[]')
                with self.assertRaises(ValueError):
                    validate_release_settings(path, target, phone_id)

if __name__ == '__main__':
    unittest.main(verbosity=2)
