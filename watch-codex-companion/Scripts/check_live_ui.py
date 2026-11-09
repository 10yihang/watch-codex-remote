#!/usr/bin/env python3
"""UI source invariants only, not Swift compilation, rendering or device tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class LiveUISourceChecks(unittest.TestCase):
    def setUp(self):
        self.phone = (ROOT / 'iPhone/LiveRemoteView.swift').read_text()
        self.watch = (ROOT / 'Watch/LiveWatchView.swift').read_text()

    def test_native_materials_accessibility_and_navigation(self):
        for source in [self.phone, self.watch]:
            for token in ['NavigationStack', 'NavigationLink', 'ScrollView',
                          'accessibilityReduceTransparency', 'colorSchemeContrast',
                          '.accessibilityHidden(true)', '.fixedSize(horizontal: false, vertical: true)']:
                self.assertIn(token, source)
            self.assertNotIn('.glassEffect(', source)
            self.assertNotIn('.font(.system(size:', source)
        self.assertIn('dynamicTypeSize.isAccessibilitySize', self.phone)
        self.assertIn('VStackLayout(alignment: .leading, spacing: 12)', self.phone)
        self.assertIn('.fill(.regularMaterial)', self.phone)
        self.assertIn('.fill(.ultraThinMaterial)', self.watch)
        self.assertIn('Color(uiColor: .secondarySystemGroupedBackground)', self.phone)
        self.assertIn('Color(white: 0.12)', self.watch)

    def test_layout_does_not_start_or_repeat_operations(self):
        for source in [self.phone, self.watch]:
            for token in ['.onAppear', '.task {', '.onChange', 'Timer.', 'DemoEngine',
                          'RemoteAPI(', 'RemoteRelay(', 'URLSession']:
                self.assertNotIn(token, source)

    def test_phone_connection_actions_and_guards(self):
        for token in ['case .signIn: controller.signIn()', 'case .restore: controller.restore()',
                      'case .enroll: controller.enroll()', 'pairingCode = ""; controller.pair(code: code)',
                      'controller.connect(hostID: id)', 'case .revoke: controller.revoke()',
                      'controller.disconnect()', 'controller.cancel()', 'controller.loadHosts()',
                      'controller.refresh()', 'controller.read(threadID: threadID)',
                      'controller.acknowledgeReviewedOutcome()',
                      '.disabled(controller.busy || controller.snapshot.connected)',
                      '.disabled(controller.busy || controller.canRevoke)',
                      '.disabled(controller.busy || !host.online)',
                      '.disabled(controller.busy || !controller.canRevoke)',
                      '.disabled(controller.busy || !controller.snapshot.connected)',
                      'controller.busy || pairingCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty']:
            self.assertIn(token, self.phone)

    def test_refresh_requires_an_existing_connection(self):
        self.assertIn('Label("刷新会话", systemImage: "arrow.clockwise")', self.phone)
        self.assertNotIn('读取主机与会话', self.phone)
        self.assertIn('.disabled(controller.busy || !controller.snapshot.connected)', self.phone)
        self.assertIn('.disabled(store.busy || !store.reachable || !store.snapshot.connected)', self.watch)
        for title in ['连接设置', '连接信息', '会话标识']:
            self.assertIn(f'Text("{title}").frame(minHeight: 44).contentShape(Rectangle())', self.phone)

    def test_confirmation_stays_before_phone_authorization(self):
        for token in ['.alert(item: $confirmation)', 'try? await Task.sleep(for: .milliseconds(350))',
                      '登录并保存凭据？', '建立持续访问权限？', '提交配对码？',
                      '连接这台主机？', '撤销控制器？', '设备专属钥匙串', '未经服务方验证']:
            self.assertIn(token, self.phone)
        self.assertIn('SecureField("配对码", text: $pairingCode)', self.phone)

    def test_phone_mutation_guards_and_success_only_draft_clear(self):
        for token in ['controller.busy || controller.needsReview || !controller.snapshot.fresh || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000',
                      'controller.busy || controller.needsReview || !controller.snapshot.fresh || thread?.currentTurnID == nil',
                      'guard command.binding == controller.snapshot.binding, controller.snapshot.fresh,',
                      '(try? command.validate()) != nil', 'let reply = await controller.handle(command: command)',
                      'if reply.state == .succeeded && command.kind == .sendText { text = "" }']:
            self.assertIn(token, self.phone)

    def test_watch_mutation_reachability_and_review_guards(self):
        for token in ['.disabled(store.busy || !store.reachable)',
                      'if store.uncertain && store.canReview', 'store.reviewed()',
                      '!store.canMutate || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000',
                      '!store.canMutate || thread?.currentTurnID == nil',
                      'if let pending { store.perform(pending) }']:
            self.assertIn(token, self.watch)
        for token in ['.signIn(', 'accessToken', 'CodexPlanTokenStore', 'RemoteConnectionController']:
            self.assertNotIn(token, self.watch)

    def test_exact_mutation_target_and_cancel_are_preserved(self):
        for source in [self.phone, self.watch]:
            for token in ['@State private var pending: LiveCommand?',
                          'kind: kind, threadID: threadID',
                          'turnID: kind == .interrupt ? thread?.currentTurnID : nil',
                          'Button("取消", role: .cancel) { pending = nil }',
                          'pending?.binding.environmentID', 'pending?.threadID', 'pending?.turnID',
                          '.alert("确认真实操作", isPresented: $showConfirmation)']:
                self.assertIn(token, source)

    def test_product_truth_and_receipts_remain_visible(self):
        for source in [self.phone, self.watch]:
            self.assertIn('实验性 · 未完成实机验证', source)
            self.assertIn('thread.state.label', source)
            self.assertIn('snapshot.hostName', source)
        for token in ['complete: controller.signedIn', 'complete: controller.enrolled',
                      'complete: controller.snapshot.connected', 'controller.reviewHostID',
                      'controller.reviewThreadID', 'binding.environmentID', 'controller.status']:
            self.assertIn(token, self.phone)
        self.assertIn('store.receipt', self.watch)
        self.assertIn('store.snapshot.generatedAt.formatted', self.watch)

if __name__ == '__main__':
    print('Checking UI source invariants only; no Swift, simulator or device validation.', flush=True)
    unittest.main(verbosity=2)
