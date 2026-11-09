#!/usr/bin/env python3
"""Structural checks only. Does not execute Swift, open a listener, or access Keychain."""
from pathlib import Path
import hashlib
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
AUTH_FILES = ['CodexPlanOAuth.swift', 'CodexPlanTokenStore.swift',
              'CodexOAuthCallbackServer.swift', 'CodexOAuthSafariPresenter.swift']

class NativeAuthSourceChecks(unittest.TestCase):
    def setUp(self):
        self.auth = {name: (ROOT/'iPhone'/name).read_text() for name in AUTH_FILES}
        self.oauth = self.auth['CodexPlanOAuth.swift']
        self.callback = self.auth['CodexOAuthCallbackServer.swift']
        self.store = self.auth['CodexPlanTokenStore.swift']
    def test_configuration_is_explicitly_experimental(self):
        info = plistlib.loads((ROOT/'iPhone/Info.plist').read_bytes())
        self.assertIs(info['CodexOAuthEnabled'], True)
        self.assertEqual(info['CodexOAuthClientID'], 'app_EMoamEEZ73f0CkXaXp7hrann')
        self.assertEqual(info['CodexOAuthScope'], 'openid profile email offline_access api.connectors.read api.connectors.invoke')
        self.assertIn('codex_cli_simplified_flow', self.oauth)
        self.assertIn('guard CodexPlanOAuthConstants.enabled,', self.oauth)
    def test_no_desktop_credential_import(self):
        for source in self.auth.values():
            for forbidden in ['auth.json', 'UserDefaults', 'NSAllowsArbitraryLoads']:
                self.assertNotIn(forbidden, source)
    def test_only_phone_controller_launches_oauth(self):
        controller = (ROOT/'iPhone/RemoteConnectionController.swift').read_text()
        self.assertIn('func signIn()', controller)
        self.assertIn('oauth.signIn(expectedAccountID:', controller)
        self.assertIn('oauth.stepUp(accountID:', controller)
        self.assertNotIn('init() {', controller)
        for path in (ROOT/'Watch').glob('*.swift'):
            source = path.read_text()
            for call in ['CodexPlanOAuth(', 'CodexPlanTokenStore(', '.signIn(', 'accessToken']:
                self.assertNotIn(call, source, str(path))
    def test_sources_are_iphone_only(self):
        project = (ROOT/'WatchCodex.xcodeproj/project.pbxproj').read_text()
        uid = lambda key: hashlib.sha256(key.encode()).hexdigest()[:24].upper()
        for name in AUTH_FILES:
            self.assertIn(uid('PhoneiPhone/'+name)+' = { isa = PBXBuildFile;', project)
            self.assertNotIn(uid('WatchiPhone/'+name), project)
    def test_callback_is_loopback_bound_and_bounded(self):
        for text in ['parameters.acceptLocalOnly = true', 'host: .ipv4(.loopback)',
                     'isLoopback(connection.endpoint)', 'maximumHeaderBytes = 16 * 1024',
                     'candidate.newConnectionLimit = 16', 'headers["host"] == ["localhost:\\(activePort)"]',
                     'states.count == 1', 'constantTimeEqual(returnedState, expectedState)',
                     'codes.count == 1', 'Cache-Control: no-store']:
            self.assertIn(text, self.callback)
    def test_cancellation_and_foreground_boundaries_are_present(self):
        for text in ['waitUntilForeground(operationID)', 'networkTask?.cancel()',
                     'await callbackServer?.cancel()', 'await dismissSafari()',
                     'try ensureActive(operationID)', 'withTaskCancellationHandler']:
            self.assertIn(text, self.oauth)
    def test_mfa_app_switch_preserves_only_interactive_authorization(self):
        self.assertNotIn('didEnterBackgroundNotification', self.oauth)
        self.assertNotIn('foregroundWatchTask', self.oauth)
        self.assertIn('sessionWindow = window', self.oauth)
        self.assertIn('try sessionWindow.validate()', self.oauth)
        self.assertIn('UIApplication.shared.applicationState == .active', self.oauth)
        self.assertIn('try await Task.sleep(for: .milliseconds(200))', self.oauth)
        self.assertEqual(self.oauth.count('let code = try await server.waitForAuthorizationCode()\n                try await waitUntilForeground(operationID)'), 2)
        app = (ROOT/'iPhone/PhoneApp.swift').read_text()
        self.assertIn('controller.applicationDidEnterBackground()', app)
        self.assertNotIn('controller.disconnect()', app)
        controller = (ROOT/'iPhone/RemoteConnectionController.swift').read_text()
        self.assertIn('guard interactiveAuthorization else { disconnect(); return }', controller)
        self.assertEqual(controller.count('try await self.withInteractiveAuthorization {'), 2)
        self.assertIn('defer { interactiveAuthorization = false }', controller)
        self.assertIn('func cancel() { disconnect() }', controller)
        self.assertIn('try await self.awaitForeground()\n            try stepUp.validate()', controller)
        self.assertNotIn('beginBackgroundTask', self.oauth + controller)
        self.assertNotIn('ASWebAuthenticationSession', self.oauth)
    def test_safari_does_not_wait_on_animation_completion(self):
        source = self.auth['CodexOAuthSafariPresenter.swift']
        for text in ['presenter.presentedViewController == nil', '!presenter.isBeingPresented',
                     '!presenter.isBeingDismissed', 'presenter.present(controller, animated: true)']:
            self.assertIn(text, source)
        self.assertNotIn('withCheckedContinuation', source)
    def test_token_transport_rejects_redirects_and_bounds_stream(self):
        for text in ['completionHandler(nil)', 'URLSessionConfiguration.ephemeral',
                     'configuration.httpCookieStorage = nil', 'configuration.urlCredentialStorage = nil',
                     'urlSession.bytes(for: request)', 'data.count < 1_048_576',
                     'request.timeoutInterval = 30', 'try Task.checkCancellation()']:
            self.assertIn(text, self.oauth)
    def test_keychain_cannot_weaken_protection_on_load(self):
        for text in ['kSecAttrAccessibleWhenUnlockedThisDeviceOnly',
                     'kSecAttrSynchronizable as String: false',
                     'kSecUseDataProtectionKeychain as String: true',
                     'keychainProtectionMismatch', 'try validate(tokens)', '<redacted>']:
            self.assertIn(text, self.store)
        self.assertEqual(self.store.count('guard data.count <= 1_048_576'), 2)
        self.assertNotIn('AfterFirstUnlock', self.store)
        self.assertNotIn('allowsBackgroundAccess', self.store)
        for source in self.auth.values():
            self.assertNotIn('print(', source)
            self.assertNotIn('Logger(', source)
    def test_auth_does_not_enroll_or_pair(self):
        for source in self.auth.values():
            for forbidden in ['RemoteDeviceKey.create(', 'RemoteAPI(',
                              '/client/enroll/', 'manual_pairing_code', 'turn/start']:
                self.assertNotIn(forbidden, source)
    def test_mit_notice_is_preserved(self):
        license_text = (ROOT/'ThirdParty/NightBloodRemote/LICENSE').read_text()
        self.assertIn('Copyright (c) 2026 NightBlood Remote contributors', license_text)
        self.assertIn('MIT License', license_text)
        self.assertTrue((ROOT/'ThirdParty/NightBloodRemote/NOTICE.md').is_file())
        for source in self.auth.values():
            self.assertIn('4824aceb1cd04ac521f7f0342771c20edad60dac', source)
            self.assertIn('Copyright (c) 2026 NightBlood Remote contributors.', source)

if __name__ == '__main__':
    print('Native OAuth source checks only; no Swift, login, network or Keychain execution.', flush=True)
    unittest.main(verbosity=2)
