import SwiftUI

/// Popover content for editing the directive of a `.inlineLLM` chain step.
///
/// Anchored under the chip via SwiftUI `.popover`. The chip's tap handler
/// drives `isPresented` and seeds the draft directive into a parent
/// `@State` binding; this view edits that binding and reports done/cancel
/// via callbacks.
///
/// **Design:**
/// - Multi-line `TextEditor` (~280×100pt) — directives can be a few
///   sentences (e.g., "summarize as 3 bullets, no preamble, plain text").
/// - Footer with Cancel + Done. ⌘⏎ commits, Esc cancels.
/// - Empty directive on commit → parent removes the chip (handled in the
///   chip editor's `commitInlineLLMEdit`).
struct InlineLLMEditPopover: View {
    @Binding var directive: String
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiPrimary)
                Text("Inline LLM directive")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.caiTextPrimary)
                Spacer()
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $directive)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .focused($editorFocused)
                if directive.isEmpty {
                    Text("e.g. summarize as 3 bullets, no preamble, plain text")
                        .font(.system(size: 12))
                        .foregroundColor(.caiTextSecondary.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 280, height: 100)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
            )

            Text("Applied to the chain pipe value. \"About You\" + per-app context snippets are injected automatically.")
                .font(.system(size: 9))
                .foregroundColor(.caiTextSecondary.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

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
        .onAppear { editorFocused = true }
    }
}
