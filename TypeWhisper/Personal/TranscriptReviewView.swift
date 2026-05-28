//  TranscriptReviewView.swift
//  TypeWhisper — PERSONAL MODIFICATION
//
//  Editable review surface shown before the transcript is inserted into the
//  target app. The user can fix mistakes; edits are inserted and learned.

import SwiftUI

struct TranscriptReviewView: View {
    @State private var text: String
    private let onInsert: (String) -> Void
    private let onCancel: () -> Void

    @FocusState private var editorFocused: Bool

    init(initialText: String, onInsert: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialText)
        self.onInsert = onInsert
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Review transcript")
                .font(.headline)

            TextEditor(text: $text)
                .font(.body)
                .focused($editorFocused)
                .frame(minWidth: 420, minHeight: 140)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3))
                )

            HStack {
                Text("\u{2318}\u{21A9} insert \u{00B7} esc cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") { onInsert(text) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(minWidth: 460)
        .onAppear { editorFocused = true }
    }
}
