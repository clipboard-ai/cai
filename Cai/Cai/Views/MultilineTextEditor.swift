import AppKit
import SwiftUI

/// Multi-line text editor that wraps `NSTextView` with the two key bindings
/// SwiftUI's stock components get wrong on macOS:
///
/// - **Plain Return → inserts newline** (NSTextView default).
///   `TextField(axis: .vertical)` swallows Return on macOS — the event
///   never produces a newline. Users can't write multi-line content.
///
/// - **⌘⏎ → forwarded to next responder** so the form-level
///   `.keyboardShortcut(.return, modifiers: .command)` on the Save button
///   fires. NSTextView's default treats ⌘⏎ as `insertLineBreak:` which
///   consumes the event before SwiftUI sees it (the very reason
///   `LLMEditPopover` had to abandon `TextEditor`).
///
/// - **Esc → forwarded** so `.keyboardShortcut(.cancelAction)` on the
///   Cancel button fires.
///
/// Use this for multi-line form fields where users need both:
/// (a) a real text editor with newline-on-Return, and
/// (b) ⌘⏎ to save / Esc to cancel the parent form.
///
/// **Visual styling:** matches the unified input shell from the editor
/// redesign — `caiSurface`-tinted background, 0.5px separator border (or
/// 1px `caiPrimary` on focus). Caller adds the rounded background; this
/// view renders the editor itself with no chrome.
struct MultilineTextEditor: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var monospaced: Bool = false
    var fontSize: CGFloat = 12
    /// Default visible-line count when the editor is empty. Combined with
    /// `maxLines`, gives "2 lines tall by default, grow with content,
    /// scroll beyond 4 lines" — matches Linear/Notion/Slack composer UX.
    var minLines: Int = 2
    var maxLines: Int = 4
    /// When true, the editor takes first-responder focus once added to a
    /// window. Use for popovers where the user expects to start typing
    /// immediately on open (e.g. the inline LLM directive editor).
    var autoFocus: Bool = false
    /// Fired when the user presses ⌘⏎. Bypasses SwiftUI's `keyboardShortcut`
    /// chain (which doesn't cooperate cleanly with NSTextView's responder
    /// chain). Set this to the parent form's save action.
    var onCommit: (() -> Void)? = nil
    /// Fired when the user presses Esc. Same rationale as `onCommit`.
    var onCancel: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = ForwardingTextView()
        textView.delegate = context.coordinator
        textView.string = text
        textView.font = effectiveFont
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.placeholderString = placeholder
        textView.shouldAutoFocusOnFirstAppear = autoFocus
        textView.onCommit = onCommit
        textView.onCancel = onCancel

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ForwardingTextView else { return }
        // Avoid stomping the user's caret position when SwiftUI re-renders
        // for a reason unrelated to the text content.
        if textView.string != text {
            textView.string = text
        }
        textView.font = effectiveFont
        textView.placeholderString = placeholder
        // Refresh callbacks each render — captures the latest closure
        // (parent's @State / bindings may have changed).
        textView.onCommit = onCommit
        textView.onCancel = onCancel
    }

    /// SwiftUI's frame helpers can read these to clamp height. Computed from
    /// `fontSize × line-count + insets` so the math matches the rendered
    /// text. ~1.4× line spacing matches NSTextView's default for system fonts.
    var minHeight: CGFloat {
        ceil(fontSize * 1.4 * CGFloat(minLines))
    }
    var maxHeight: CGFloat {
        ceil(fontSize * 1.4 * CGFloat(maxLines))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    private var effectiveFont: NSFont {
        monospaced
            ? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            : NSFont.systemFont(ofSize: fontSize)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineTextEditor

        init(_ parent: MultilineTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }
    }
}

// MARK: - NSTextView subclass with placeholder + key forwarding

/// `NSTextView` subclass that:
/// - Renders a placeholder when empty (NSTextView has no built-in
///   placeholder support).
/// - Forwards `⌘⏎` and `Esc` to the next responder so the parent form's
///   keyboard shortcuts fire instead of being eaten by the text view.
private final class ForwardingTextView: NSTextView {
    var placeholderString: String = "" {
        didSet { needsDisplay = true }
    }
    var shouldAutoFocusOnFirstAppear: Bool = false
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    private var hasAutoFocused: Bool = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard shouldAutoFocusOnFirstAppear, !hasAutoFocused, window != nil else { return }
        hasAutoFocused = true
        // Defer to next runloop tick so the window's responder chain is
        // fully wired before we ask it to make us first responder.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    /// Intercept ⌘⏎ at performKeyEquivalent (fires BEFORE keyDown). Direct
    /// callback bypasses SwiftUI's `.keyboardShortcut` chain entirely —
    /// experiments showed forwarding via `nextResponder` doesn't reliably
    /// route to the form's Save button when focus is in NSTextView.
    /// Returning `true` marks the event handled so NSTextView's default
    /// `insertLineBreak:` doesn't also fire.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let cmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        if cmd, event.charactersIgnoringModifiers == "\r" {
            if let onCommit = onCommit {
                onCommit()
                return true
            }
            return false  // no callback wired — let it propagate
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Esc → fire onCancel callback directly. Same rationale as ⌘⏎: the
    /// SwiftUI shortcut chain was being intercepted by Cai's window-level
    /// Esc handler before the form's Cancel button could see it.
    override func cancelOperation(_ sender: Any?) {
        if let onCancel = onCancel {
            onCancel()
        } else {
            nextResponder?.cancelOperation(sender)
        }
    }

    /// Tab → move focus to the next form field instead of inserting a
    /// tab character. Standard macOS form-field convention. Note: SwiftUI
    /// doesn't always wire its hosted views into the AppKit key view loop,
    /// so this can be a no-op in some contexts. Acceptable degradation —
    /// user can click between fields.
    override func insertTab(_ sender: Any?) {
        window?.selectNextKeyView(self)
    }

    override func insertBacktab(_ sender: Any?) {
        window?.selectPreviousKeyView(self)
    }

    // Placeholder rendering — drawn behind the text when string is empty.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholderString.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.4)
        ]
        let inset = textContainerInset
        let origin = NSPoint(
            x: inset.width + (textContainer?.lineFragmentPadding ?? 5),
            y: inset.height
        )
        placeholderString.draw(at: origin, withAttributes: attrs)
    }
}

// MARK: - Form field shell modifier
//
// Shared visual treatment for ALL form input fields across both editors
// (Custom Actions + Destinations). One source of truth for background,
// border, focus highlight — change here, propagates everywhere.

extension View {
    /// Wraps a form input field in the standard Cai input shell:
    /// `caiSurface`-tinted background, hairline separator border (or
    /// `caiPrimary` border when `focused`), 6pt corner radius, 8pt inner
    /// padding. Use for all form text inputs (multi-line and single-line)
    /// to keep visual rhythm consistent across editors.
    func formFieldShell(focused: Bool = false) -> some View {
        self
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .textBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        focused ? Color.caiPrimary.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.5),
                        lineWidth: focused ? 1.0 : 0.5
                    )
            )
    }
}
