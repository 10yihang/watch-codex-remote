// Adapted from NightBlood Remote, commit 4824aceb1cd04ac521f7f0342771c20edad60dac.
// Copyright (c) 2026 NightBlood Remote contributors. MIT License.
// See ../ThirdParty/NightBloodRemote/LICENSE and NOTICE.md.
// Dormant preparation only: no UI/launch call sites, login or account enrollment.

import Foundation
@preconcurrency import SafariServices
@preconcurrency import UIKit

/// A handle returned by the presentation closure. The OAuth actor uses it to
/// dismiss Safari after success, cancellation, timeout or failure.
public struct CodexOAuthSafariSession: Sendable {
    private let dismissal: @MainActor @Sendable () -> Void

    public init(dismiss: @escaping @MainActor @Sendable () -> Void) {
        self.dismissal = dismiss
    }

    @MainActor
    public func dismiss() {
        dismissal()
    }
}

/// The caller supplies this closure so the reusable OAuth module has no view
/// hierarchy assumptions. It must present the URL in SFSafariViewController.
public typealias CodexOAuthSafariPresentation = @MainActor @Sendable (
    _ authorizationURL: URL,
    _ userCancelled: @escaping @Sendable () -> Void
) async throws -> CodexOAuthSafariSession

/// Optional UIKit implementation of `CodexOAuthSafariPresentation` for a
/// caller that already has the view controller from which Safari should open.
@MainActor
public final class CodexOAuthSafariViewControllerPresenter: NSObject,
    @preconcurrency SFSafariViewControllerDelegate,
    UIAdaptivePresentationControllerDelegate
{
    private weak var presentingViewController: UIViewController?
    private weak var currentSafariViewController: SFSafariViewController?
    private var cancellation: (@Sendable () -> Void)?

    public init(presentingViewController: UIViewController) {
        self.presentingViewController = presentingViewController
        super.init()
    }

    public func presentation() -> CodexOAuthSafariPresentation {
        { [weak self] url, userCancelled in
            guard let self else {
                throw CodexPlanOAuthError.browserPresenterUnavailable
            }
            return try await self.present(url: url, userCancelled: userCancelled)
        }
    }

    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        handleUserDismissal(of: controller)
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let controller = presentationController.presentedViewController
                as? SFSafariViewController
        else { return }
        handleUserDismissal(of: controller)
    }

    private func present(
        url: URL,
        userCancelled: @escaping @Sendable () -> Void
    ) async throws -> CodexOAuthSafariSession {
        guard let presenter = presentingViewController,
              presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil,
              !presenter.isBeingPresented,
              !presenter.isBeingDismissed,
              currentSafariViewController == nil
        else {
            throw CodexPlanOAuthError.browserPresenterUnavailable
        }

        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .cancel
        controller.delegate = self
        currentSafariViewController = controller
        cancellation = userCancelled

        // The callback server already owns the bounded login timeout. Return
        // its dismissal handle immediately rather than suspending on a UIKit
        // animation completion that may not fire if presentation is refused.
        presenter.present(controller, animated: true)
        controller.presentationController?.delegate = self

        return CodexOAuthSafariSession { [weak self, weak controller] in
            guard let self else {
                controller?.dismiss(animated: true)
                return
            }
            if self.currentSafariViewController === controller {
                self.currentSafariViewController = nil
                self.cancellation = nil
            }
            controller?.dismiss(animated: true)
        }
    }

    private func handleUserDismissal(of controller: SFSafariViewController) {
        guard currentSafariViewController === controller else { return }
        currentSafariViewController = nil
        let action = cancellation
        cancellation = nil
        action?()
    }
}
