#!/usr/bin/env python3
"""Capture actual demo app pixels on disposable CI simulators after verify_apple.sh.
No UI is redrawn and no real Remote account, host, or physical device is accessed.
"""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / '.build' / 'screenshots'
OUTPUT.mkdir(parents=True, exist_ok=True)


def run(*args, timeout=180):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), check=True, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
    print(result.stdout, end='', flush=True)
    return result.stdout


def select_device(devices, platform, preferred, sdk_version):
    candidates = []
    for runtime, entries in devices.items():
        if f'.{platform}-' not in runtime:
            continue
        version = tuple(map(int, re.findall(r'\d+', runtime.split(f'.{platform}-')[-1])))
        # A runner may list runtimes newer than its selected Xcode can reliably launch.
        if version > sdk_version:
            continue
        for device in entries:
            if device.get('isAvailable') and (platform != 'iOS' or device['name'].startswith('iPhone')):
                preference = next((len(preferred) - i for i, word in enumerate(preferred)
                                   if word in device['name']), 0)
                candidates.append((version, preference, device['name'], runtime, device))
    if not candidates:
        raise RuntimeError(f'No available {platform} simulator runtime/device.')
    _, _, _, runtime, device = max(candidates, key=lambda item: item[:3])
    return {**device, 'runtime': runtime}


def capture(device, app, bundle, filename, appearance=None, content_size=None):
    udid = device['udid']
    if device['state'] != 'Booted':
        run('xcrun', 'simctl', 'boot', udid)
        device['state'] = 'Booted'
    run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=480)
    if not device.get('installed'):
        run('xcrun', 'simctl', 'install', udid, app)
        device['installed'] = True
    if appearance:
        run('xcrun', 'simctl', 'ui', udid, 'appearance', appearance)
    if content_size:
        run('xcrun', 'simctl', 'ui', udid, 'content_size', content_size)
    launch = run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid, bundle,
                 '-AppleLanguages', '(zh-Hans)', '-AppleLocale', 'zh_CN', timeout=300)
    time.sleep(10)  # Allow first-launch SwiftUI layout and system animations to finish.
    path = OUTPUT / filename
    run('xcrun', 'simctl', 'io', udid, 'screenshot', '--type=png', path)
    if not path.exists() or path.stat().st_size < 1000:
        raise RuntimeError(f'Capture missing or unexpectedly small: {filename}')
    return {'file': filename, 'device': device['name'], 'runtime': device['runtime'],
            'bundle': bundle, 'appearance': appearance or 'watchOS default',
            'content_size': content_size or 'default', 'launch': launch.strip(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    inventory = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))
    (OUTPUT / 'simulator-inventory.json').write_text(json.dumps(inventory, indent=2))
    phone_sdk = tuple(map(int, run('xcrun', '--sdk', 'iphonesimulator', '--show-sdk-version').strip().split('.')))
    watch_sdk = tuple(map(int, run('xcrun', '--sdk', 'watchsimulator', '--show-sdk-version').strip().split('.')))
    phone = select_device(inventory['devices'], 'iOS', ['iPhone 16 Pro Max', 'iPhone 16 Pro', 'iPhone'], phone_sdk)
    watch = select_device(inventory['devices'], 'watchOS', ['Ultra 2', '46mm', '45mm', 'Apple Watch'], watch_sdk)
    small_watch = select_device(inventory['devices'], 'watchOS', ['42mm', '41mm', '40mm'], watch_sdk)
    products = ROOT / '.build' / 'apple' / 'Build' / 'Products'
    phone_app = products / 'Debug-iphonesimulator' / 'WatchCodexPhone.app'
    watch_app = products / 'Debug-watchsimulator' / 'WatchCodexWatch.app'
    metadata = {'commit': os.environ.get('GITHUB_SHA'), 'run_id': os.environ.get('GITHUB_RUN_ID'),
                'created_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'scope': 'Actual simulator screenshots of the unconnected experimental setup UI. No login or Remote request is performed. No physical-device or end-to-end connectivity verification.',
                'captures': []}
    try:
        metadata['captures'].append(capture(phone, phone_app, 'org.example.watchcodex', 'iphone-setup-light.png', 'light'))
        metadata['captures'].append(capture(phone, phone_app, 'org.example.watchcodex', 'iphone-setup-dark.png', 'dark'))
        metadata['captures'].append(capture(phone, phone_app, 'org.example.watchcodex', 'iphone-setup-accessibility.png', 'light', 'accessibility-large'))
        metadata['captures'].append(capture(watch, watch_app, 'org.example.watchcodex.watchkitapp', 'watch-setup.png'))
        if small_watch['udid'] != watch['udid']:
            metadata['captures'].append(capture(small_watch, watch_app, 'org.example.watchcodex.watchkitapp', 'watch-setup-small.png'))
    finally:
        (OUTPUT / 'capture-evidence.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
    print('Captured actual simulator app screens. Human visual review is still required.')


if __name__ == '__main__':
    main()
