#!/usr/bin/env python3
"""Source/project checks only. Never a substitute for Swift compilation or device tests."""
from pathlib import Path
import hashlib
import importlib.util
import json
import plistlib
import re
import subprocess
import shutil
import tempfile
import sys
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
class SourceChecks(unittest.TestCase):
    def setUp(self):
        self.project = (ROOT/'WatchCodex.xcodeproj/project.pbxproj').read_text()
        self.core = (ROOT/'Shared/Core.swift').read_text()
        self.store = (ROOT/'Shared/CompanionStore.swift').read_text()
        self.transport = (ROOT/'Shared/Connectivity.swift').read_text()
    def test_two_modern_application_targets(self):
        self.assertEqual(self.project.count('isa = PBXNativeTarget;'), 2)
        self.assertEqual(self.project.count('productType = "com.apple.product-type.application";'), 2)
        self.assertNotIn('watchkit2-extension', self.project)
    def test_all_object_references_resolve(self):
        defined = re.findall(r'^([A-F0-9]{24}) = ', self.project, re.M)
        used = re.findall(r'\b[A-F0-9]{24}\b', self.project)
        self.assertEqual(len(defined), len(set(defined)))
        self.assertEqual(set(used), set(defined))
    def test_source_files_exist_and_are_in_each_target(self):
        for source in re.findall(r'path = "([^"]+\.swift)";', self.project):
            self.assertTrue((ROOT/source).is_file(), source)
        self.assertEqual(self.project.count('isa = PBXSourcesBuildPhase;'), 2)
        self.assertEqual(self.project.count('isa = PBXBuildFile;'), 35)  # 32 source + 2 assets + 1 embed
    def test_companion_bundle_identifiers_match(self):
        subprocess.run([sys.executable, str(ROOT/'Scripts/check_bundle_configuration.py')], check=True, capture_output=True)
    def test_embed_phase_and_dependency_exist(self):
        self.assertIn('dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16;', self.project)
        self.assertEqual(self.project.count('isa = PBXTargetDependency;'), 1)
    def test_schemes_are_well_formed_and_match_targets(self):
        for name in ['Phone','Watch']:
            scheme = ET.parse(ROOT/f'WatchCodex.xcodeproj/xcshareddata/xcschemes/WatchCodex{name}.xcscheme')
            refs = scheme.findall('.//BuildableReference')
            self.assertEqual(len(refs),3)
            for ref in refs:
                self.assertIn(ref.attrib['BlueprintIdentifier']+' = { isa = PBXNativeTarget;',self.project)
                self.assertEqual(ref.attrib['BuildableName'],f'WatchCodex{name}.app')
    def test_remote_implementation_cannot_borrow_desktop_auth(self):
        sources = '\n'.join(path.read_text() for folder in ['Shared', 'iPhone', 'Watch'] for path in (ROOT/folder).glob('*.swift'))
        for forbidden in ['auth.json', 'NSAllowsArbitraryLoads']:
            self.assertNotIn(forbidden,sources)
        ui = '\n'.join((ROOT/p).read_text() for p in ['iPhone/PhoneApp.swift', 'iPhone/PhoneRootView.swift', 'Shared/CompanionStore.swift'])
        for forbidden in ['RemoteAPI(', 'RemoteRelay(', 'RemoteDeviceKey.create(', 'CodexPlanOAuth(', '.signIn(', 'CodexPlanTokenStore(']:
            self.assertNotIn(forbidden, ui)
    def test_remote_transport_is_existing_thread_only_and_redirects_are_denied(self):
        relay = (ROOT/'Shared/RemoteRelay.swift').read_text()
        api = (ROOT/'Shared/RemoteAPI.swift').read_text()
        for source in [relay, api]:
            self.assertIn('completionHandler(nil)', source)
            self.assertIn('URLSessionConfiguration.ephemeral', source)
        for forbidden in ['"thread/start"', '"thread/fork"']:
            self.assertNotIn(forbidden, relay)
        self.assertIn('maximumMessageSize', relay)
        for method in ['thread/resume', 'turn/start', 'turn/interrupt']:
            self.assertIn(method, relay)
        self.assertIn('outcomeUnknown', relay)
        self.assertIn('guard data.count < Self.maxResponseBytes', api)
    def test_live_source_separated_and_no_launch_side_effects(self):
        controller = (ROOT/'iPhone/RemoteConnectionController.swift').read_text()
        wire = (ROOT/'Shared/LiveWire.swift').read_text()
        self.assertNotIn('DemoEngine', controller)
        self.assertIn('codex.remote.live.v1', wire)
        self.assertNotIn('init() {', controller)
        for path in ['iPhone/PhoneApp.swift', 'Watch/WatchApp.swift']:
            source = (ROOT/path).read_text()
            self.assertNotIn('.signIn()', source)
            self.assertNotIn('.enroll()', source)
        self.assertIn('phase = .enrollmentUnknown; try saved.save()', controller)
        self.assertIn('saved.pendingMutation = .init', controller)
        self.assertIn('try saved.save(); setJournal(saved)', controller)
        self.assertIn('recentRequestIDs.contains(command.id)', controller)
        self.assertIn('pending.environmentID == snapshot.binding?.environmentID', controller)
    def test_credentials_do_not_enter_watch_payload(self):
        wire = (ROOT/'Shared/LiveWire.swift').read_text()
        for forbidden in ['accessToken', 'refreshToken', 'remoteControlToken', 'wrappedKey', 'stepUpToken']:
            self.assertNotIn(forbidden, wire)
        journal = (ROOT/'iPhone/RemoteConnectionJournal.swift').read_text()
        self.assertIn('kSecAttrAccessibleWhenUnlockedThisDeviceOnly', journal)
        self.assertIn('kSecAttrSynchronizable as String: false', journal)
        self.assertNotIn('UserDefaults', journal)
    def test_native_auth_guardrails(self):
        subprocess.run([sys.executable, str(ROOT/'Scripts/check_native_auth.py')], check=True, capture_output=True)
    def test_live_ui_guardrails(self):
        subprocess.run([sys.executable, str(ROOT/'Scripts/check_live_ui.py')], check=True, capture_output=True)
    def test_device_key_guardrails(self):
        subprocess.run([sys.executable, str(ROOT/'Scripts/check_device_key.py')], check=True, capture_output=True)
    def test_new_native_remote_tests_are_in_swift_package(self):
        package = (ROOT/'Package.swift').read_text()
        for name in ['RemoteSigning', 'RemoteRelay', 'RemoteAPI']:
            self.assertIn(f'"{name}.swift"', package)
            self.assertTrue((ROOT/f'Tests/CompanionCoreTests/{name}Tests.swift').is_file())
    def test_commands_are_not_background_queued(self):
        self.assertIn('session.isReachable', self.transport)
        self.assertIn('session.activationState == .activated', self.transport)
        self.assertNotIn('transferUserInfo',self.transport)
        self.assertIn('reply.requestID == command.id',self.transport)
        self.assertIn('DispatchQueue.main.async',self.transport)
    def test_unknown_mutation_stays_blocked_on_failed_refresh(self):
        self.assertNotIn('uncertainMutation = command.kind != .refresh',self.store)
        self.assertEqual(self.store.count('if command.kind != .refresh { self.uncertainMutation = true }'),2)
        self.assertIn('command.kind == .refresh && reply.state == .demoApplied',self.store)
    def test_no_thread_creation_or_fork_command(self):
        self.assertIn('case refresh, sendText, interrupt',self.core)
        self.assertNotIn('case create',self.core)
        self.assertNotIn('case fork',self.core)
    def test_native_ui_is_explicitly_demo_and_source_switch_disabled(self):
        phone=(ROOT/'iPhone/PhoneRootView.swift').read_text()
        watch=(ROOT/'Watch/WatchRootView.swift').read_text()
        for text in [phone,watch]:
            self.assertIn('模拟发送',text)
            self.assertIn('模拟停止',text)
            self.assertIn('Remote',text)
        self.assertIn('isOn: $store.usePhone).disabled(store.busy)',watch)
        self.assertNotIn('.font(.system(size:',phone+watch)
    def test_capture_uses_sdk_compatible_runtime(self):
        spec = importlib.util.spec_from_file_location('capture', ROOT/'Scripts/capture_simulators.py')
        capture = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(capture)
        device = {'isAvailable': True, 'name': 'iPhone 16 Pro Max'}
        inventory = {'com.apple.CoreSimulator.SimRuntime.iOS-18-5': [dict(device, udid='supported')],
                     'com.apple.CoreSimulator.SimRuntime.iOS-26-2': [dict(device, udid='too-new')]}
        selected = capture.select_device(inventory, 'iOS', ['iPhone'], (18, 5))
        self.assertEqual(selected['udid'], 'supported')
        with self.assertRaises(RuntimeError):
            capture.select_device(inventory, 'iOS', ['iPhone'], (17, 0))
    def test_phone_navigation_survives_session_state_changes(self):
        source = (ROOT/'iPhone/PhoneRootView.swift').read_text()
        self.assertEqual(source.count('NavigationLink(value: thread.id) {'), 2)
        self.assertIn('.navigationDestination(for: String.self)', source)
        self.assertNotIn('NavigationLink { PhoneThreadView(threadID: thread.id) }', source)
    def test_native_glass_uses_supported_materials(self):
        phone = (ROOT/'iPhone/PhoneRootView.swift').read_text()
        watch = (ROOT/'Watch/WatchRootView.swift').read_text()
        for source in [phone, watch]:
            self.assertIn('.background(.ultraThinMaterial', source)
            self.assertNotIn('.glassEffect(', source)  # Requires a newer SDK than CI.
        self.assertIn('Color.primary.opacity(0.65)', phone)
        self.assertIn('AnyLayout(VStackLayout(alignment: .leading, spacing: 8))', phone)
    def test_watch_uses_readable_dark_appearance(self):
        source = (ROOT/'Watch/WatchApp.swift').read_text()
        self.assertIn('.environment(\\.colorScheme, .dark)', source)
        self.assertIn('.tint(watchAccent).accentColor(watchAccent)', source)
        watch = (ROOT/'Watch/WatchRootView.swift').read_text()
        self.assertIn('let watchAccent = Color(red: 0.424, green: 0.894, blue: 0.933)', watch)
        self.assertNotIn('Color.accentColor', watch)
    def test_background_task_waits_until_session_data_drained(self):
        source = (ROOT/'Watch/WatchApp.swift').read_text()
        self.assertIn('pendingConnectivityTasks.append(connectivityTask)', source)
        self.assertIn('guard session.activationState == .activated, !session.hasContentPending else { return }', source)
        self.assertIn('session.observe(\\.hasContentPending', source)
    def test_stop_confirmation_captures_selected_turn(self):
        for name in ['iPhone/PhoneRootView.swift','Watch/WatchRootView.swift']:
            source = (ROOT/name).read_text()
            self.assertIn('stopTarget = thread; confirmStop = true', source)
            self.assertIn('if let target = stopTarget { store.stop(target) }', source)
    def test_accent_contrast_on_light_and_dark_background(self):
        data=json.loads((ROOT/'Shared/Assets.xcassets/AccentColor.colorset/Contents.json').read_text())
        def luminance(c):
            linear=[v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in c]
            return sum(a*b for a,b in zip(linear,[0.2126,0.7152,0.0722]))
        for item in data['colors']:
            c=item['color']['components']; lum=luminance([float(c[k]) for k in ['red','green','blue']])
            dark=any(a['value']=='dark' for a in item.get('appearances',[]))
            ratio=(lum+0.05)/0.05 if dark else 1.05/(lum+0.05)
            self.assertGreaterEqual(ratio,4.5)
    def test_temporary_inactive_wait_never_allows_background_work(self):
        controller = (ROOT/'iPhone/RemoteConnectionController.swift').read_text()
        key = (ROOT/'iPhone/RemoteDeviceKey.swift').read_text()
        gate = (ROOT/'Shared/RemoteActivityGate.swift').read_text()
        errors = (ROOT/'iPhone/RemoteConnectionJournal.swift').read_text()
        self.assertIn('if state == .background { return .background }', gate)
        self.assertIn('guard protectedDataAvailable else', gate)
        self.assertIn('UIApplication.shared.isProtectedDataAvailable', controller)
        self.assertIn('case .wait: try await Task.sleep(for: .milliseconds(100))', controller)
        self.assertIn('try await awaitForeground(); try command.validate()', controller)
        self.assertGreaterEqual(controller.count('try command.validate()'), 4)
        self.assertIn('let signature = try await RemoteDeviceKey.signAsync(record: record, payload: payload)\n                    try await self.awaitForeground()', controller)
        self.assertIn('Task.detached(priority: .userInitiated)', key)
        self.assertIn('onCancel: { task.cancel() }', key)
        self.assertNotIn('try RemoteDeviceKey.sign(', controller)
        self.assertNotIn('请保持 iPhone App 在前台并解锁后操作', errors)
        self.assertIn('case .chunksUnsupported:', controller)
        self.assertIn('case .frameTooLarge:', controller)
        self.assertIn('operationStage + "：" + Self.safeMessage(error)', controller)

    def test_watch_native_accent_is_bright_in_every_appearance(self):
        uid = lambda key: hashlib.sha256(key.encode()).hexdigest()[:24].upper()
        for mode in ['Debug', 'Release']:
            for target, accent in [('Phone', 'AccentColor'), ('Watch', 'WatchAccent')]:
                line = next(line for line in self.project.splitlines() if line.startswith(uid(target+mode)+' = '))
                self.assertIn('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = "'+accent+'"', line)
        data = json.loads((ROOT/'Shared/Assets.xcassets/WatchAccent.colorset/Contents.json').read_text())
        for item in data['colors']:
            c = item['color']['components']
            rgb = [float(c[k]) for k in ['red', 'green', 'blue']]
            linear = [v/12.92 if v <= 0.04045 else ((v+0.055)/1.055)**2.4 for v in rgb]
            luminance = sum(a*b for a,b in zip(linear, [0.2126, 0.7152, 0.0722]))
            self.assertGreaterEqual((luminance+0.05)/0.05, 4.5)

    def test_generator_is_deterministic(self):
        # Never regenerate in the original checkout: it may contain local signing IDs.
        files = ['WatchCodex.xcodeproj/project.pbxproj', 'iPhone/Info.plist', 'Watch/Info.plist',
                 'WatchCodex.xcodeproj/xcshareddata/xcschemes/WatchCodexPhone.xcscheme',
                 'WatchCodex.xcodeproj/xcshareddata/xcschemes/WatchCodexWatch.xcscheme']
        with tempfile.TemporaryDirectory(prefix='watchcodex-template-') as directory:
            sandbox = Path(directory)
            (sandbox/'Scripts').mkdir()
            shutil.copy2(ROOT/'Scripts/generate_project.py', sandbox/'Scripts/generate_project.py')
            for name in files:
                (sandbox/name).parent.mkdir(parents=True, exist_ok=True)
            command = [sys.executable, str(sandbox/'Scripts/generate_project.py')]
            subprocess.run(command, check=True, capture_output=True)
            first = [(sandbox/name).read_bytes() for name in files]
            subprocess.run(command, check=True, capture_output=True)
            self.assertEqual(first, [(sandbox/name).read_bytes() for name in files])
            for name, generated in zip(files, first):
                self.assertEqual((ROOT/name).read_bytes(), generated,
                                 name + ': source template differs; personalized project was not modified')
    def test_swift_tests_present_but_not_claimed_executed(self):
        tests=(ROOT/'Tests/CompanionCoreTests/CoreTests.swift').read_text()
        self.assertEqual(len(re.findall(r'func test\w+\(',tests)),18)

if __name__ == '__main__':
    print('Checking project/source structure only; Swift/Xcode execution is separate.',flush=True)
    unittest.main(verbosity=2)
