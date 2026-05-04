import SwiftUI

/// Popover content for editing the directive of a `.inlineLLM` chain step.
///
/// Anchored under the chip row by SwiftUI `.popover` (one per editor, not
/// per chip — per-chip popovers were creating N NSPopover instances and
/// the first open was noticeably slow).
///
/// **Design:**
/// - Multi-line `TextField(axis: .vertical)` (NOT `TextEditor`) — the
///   former doesn't intercept ⌘⏎ at the responder chain, so the SwiftUI
///   `keyboardShortcut(.return, modifiers: .command)` on Done actually
///   fires. With TextEditor, ⌘⏎ was being eaten by NSTextView before
///   SwiftUI saw it.
/// - Footer with Cancel + Done. ⌘⏎ commits, Esc cancels.
/// - Empty directive on commit → parent removes the chip (handled in the
///   chip editor's `commitLLMEdit`).
struct LLMEditPopover: View {
    @Binding var directive: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiPrimary)
                Text("LLM directive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.caiTextPrimary)
                Spacer()
            }

            // `TextField` with `axis: .vertical` (macOS 14+) gives us a
            // multi-line input that — unlike TextEditor — doesn't consume
            // ⌘⏎ before the keyboardShortcut handler sees it.
            TextField(
                "e.g. summarize as 3 bullets, no preamble, plain text",
                text: $directive,
                axis: .vertical
            )
            .lineLimit(3...8)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(8)
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .focused($fieldFocused)

            Text("Applied to the chain pipe value.")
                .font(.system(size: 9))
                .foregroundColor(.caiTextSecondary.opacity(0.6))

            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .font(.system(size: 11))
                    .foregroundColor(.caiTextSecondary)
                Spacer()
                Button(action: onCommit) {
                    Text("Done")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(directive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                      ? Color.caiPrimary.opacity(0.4)
                                      : Color.caiPrimary)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .onAppear { fieldFocused = true }
    }
}
