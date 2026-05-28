//  TranscriptReviewController.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Presents the editable review window and bridges it to the async dictation
//  pipeline. The critical detail is FOCUS RESTORATION: TypeWhisper must briefly
//  activate to let the user edit, then re-activate the original target app
//  before the transcript is pasted — otherwise the paste lands in the wrong
//  place.

import AppKit
import SwiftUI

@MainActor
final class TranscriptReviewController {
    static let shared = TranscriptReviewController()

    private var panel: NSPanel?
    private var continuation: CheckedContinuation<String?, Never>?
    private var targetApp: NSRunningApplication?

    private init() {}

    /// Presents the review window for `original` and resolves with the edited
    /// text, or nil if the user cancelled. Captures and restores the target app
    /// so insertion lands in the right place.
    func review(original: String) async -> String? {
        // Remember who was in front so we can paste back into it.
        targetApp = NSWorkspace.shared.frontmostApplication

        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.continuation = cont
            self.presentPanel(initialText: original)
        }
    }

    private func presentPanel(initialText: String) {
        let view = TranscriptReviewView(
            initialText: initialText,
            onInsert: { [weak self] edited in self?.finish(with: edited) },
            onCancel: { [weak self] in self?.finish(with: nil) }
        )

        let hosting = NSHostingController(rootView: view)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .utilityWindow]
        panel.title = String(localized: "Review transcript")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.center()
        self.panel = panel

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func finish(with edited: String?) {
        // Tear down the panel.
        panel?.orderOut(nil)
        panel = nil

        let cont = continuation
        continuation = nil

        // Restore the target app so the paste goes to the right window, then
        // resume after a short delay to let activation settle.
        let app = targetApp
        targetApp = nil
        app?.activate()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            cont?.resume(returning: edited)
        }
    }
}
