#!/usr/bin/env python3
"""Validate processed Apple plists and xcodebuild JSON; never modify a project."""
import argparse
import json
from pathlib import Path
import plistlib


def read_bundle_pair(phone_app, watch_app, expected_phone=None):
    phone = plistlib.loads((Path(phone_app)/'Info.plist').read_bytes())
    watch = plistlib.loads((Path(watch_app)/'Info.plist').read_bytes())
    phone_id = phone['CFBundleIdentifier']
    watch_id = watch['CFBundleIdentifier']
    companion_id = watch['WKCompanionAppBundleIdentifier']
    for value in [phone_id, watch_id, companion_id]:
        if not isinstance(value, str) or not value or '$' in value:
            raise ValueError(f'Invalid or unexpanded processed identifier: {value!r}')
    if companion_id != phone_id:
        raise ValueError(f'Watch companion {companion_id!r} does not match Phone {phone_id!r}')
    if not watch_id.startswith(phone_id + '.'):
        raise ValueError(f'Watch identifier {watch_id!r} must be prefixed by Phone {phone_id!r}')
    if expected_phone is not None and (phone_id != expected_phone or watch_id != expected_phone+'.watchkitapp'):
        raise ValueError('Processed bundle identifiers did not use the validation override')
    return phone_id, watch_id


def validate_release_settings(path, target, expected_phone):
    entries = json.loads(Path(path).read_text())
    matches = [item['buildSettings'] for item in entries if item.get('target') == target]
    if len(matches) != 1:
        raise ValueError(f'Expected exactly one {target} build-settings entry')
    settings = matches[0]
    expected_bundle = expected_phone + ('.watchkitapp' if target == 'WatchCodexWatch' else '')
    for name, expected in [('CONFIGURATION', 'Release'), ('WATCH_CODEX_PHONE_BUNDLE_ID', expected_phone),
                           ('PRODUCT_BUNDLE_IDENTIFIER', expected_bundle)]:
        if settings.get(name) != expected:
            raise ValueError(f'{target}: {name} was {settings.get(name)!r}, expected {expected!r}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--products', type=Path, required=True)
    parser.add_argument('--expected-phone', required=True)
    parser.add_argument('--phone-release-settings', type=Path, required=True)
    parser.add_argument('--watch-release-settings', type=Path, required=True)
    args = parser.parse_args()
    phone = args.products/'Debug-iphonesimulator/WatchCodexPhone.app'
    watch = args.products/'Debug-watchsimulator/WatchCodexWatch.app'
    read_bundle_pair(phone, watch, args.expected_phone)
    # Validate the Watch actually embedded in the phone product as well.
    read_bundle_pair(phone, phone/'Watch/WatchCodexWatch.app', args.expected_phone)
    validate_release_settings(args.phone_release_settings, 'WatchCodexPhone', args.expected_phone)
    validate_release_settings(args.watch_release_settings, 'WatchCodexWatch', args.expected_phone)
    print('Validated non-default Debug processed bundle IDs (including embedded Watch) and Release settings.')


if __name__ == '__main__':
    main()
