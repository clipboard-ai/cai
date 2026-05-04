import AppKit
import SwiftUI

/// SwiftUI-native chip input for editing chain step lists. Replaces the
/// previous NSTokenField wrapper because AppKit's chip rendering can't be
/// restyled to match Cai's design system without private APIs.
///
/// **Visual language**: chips inherit `DestinationChip`'s vocabulary —
/// `caiPrimary.opacity(0.12)` fill, 6pt corner radius, 11pt medium label,
/// caiPrimary border at 0.25 alpha. The input field uses Cai's standard
/// rounded-border treatment (focus brightens the border to `caiPrimary`).
///
/// **Interaction**:
/// - Type to search → autocomplete dropdown shows matching action names
/// - Click suggestion or press ⏎/comma to commit a chip
/// - Backspace at the empty field deletes the previous chip
/// - Click the × on a chip to remove it
/// - Chips wrap to multiple lines via the embedded `FlowLayout`
///
/// Storage stays `[String]` (matches `CaiShortcut.next` /
/// `OutputDestination.next`) so this is a drop-in replacement.
struct ChainStepsTokenField: View {
    @Binding var tokens: [String]
    /// Pool of names available for autocomplete. Typically the union of
    /// shortcut + destination names visible to the user. Read on each render
    /// so settings changes flow through without manual refresh.
    let availableNames: [String]
    let placeholder: String

    @State private var inputText: String = ""
    @FocusState private var fieldIsFocused: Bool

    /// Maximum suggestions shown in the dropdown. 6 keeps the popover
    /// scannable without overwhelming the editor's vertical real estate.
    private static let maxSuggestions = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            chipRow
            if fieldIsFocused && !suggestions.isEmpty {
                suggestionsDropdown
            }
        }
    }

    // MARK: - Chip row (chips + inline TextField, wrapped via FlowLayout)

    private var chipRow: some View {
        // Reuses `FlowLayout` from `MCPFormView.swift` — same wrapping
        // behavior the MCP form uses for multiselect chips. One spacing arg
        // is fine; rows naturally inherit it for vertical gap too.
        FlowLayout(spacing: 6) {
            ForEach(tokens, id: \.self) { token in
                chip(for: token)
            }
            inputField
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(
                    fieldIsFocused ? Color.caiPrimary.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: fieldIsFocused ? 1.0 : 0.5
                )
        )
        // Tap anywhere in the empty space to focus the input — matches the
        // expected behavior of any chip-input (NSTokenField, Mail's "To:").
        .contentShape(Rectangle())
        .onTapGesture {
            fieldIsFocused = true
        }
    }

    private func chip(for token: String) -> some View {
        HStack(spacing: 4) {
            // Tiny icon to hint at type — not strictly necessary, but it
            // mirrors DestinationChip and helps the user scan a multi-step
            // chain at a glance. Falls back to "bolt" for shortcut-style
            // names; could be smarter once we surface type info upstream.
            Image(systemName: iconForName(token))
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.caiPrimary)

            Text(token)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.caiTextPrimary)
                .lineLimit(1)

            Button(action: { remove(token) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.caiTextSecondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Remove \(token)")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.caiPrimary.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color.caiPrimary.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var inputField: some View {
        TextField(tokens.isEmpty ? placeholder : "", text: $inputText)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($fieldIsFocused)
            .frame(minWidth: 100)
            // Comma autocompletes the in-progress text as a chip — feels
            // natural for users who think "comma-separated names" from the
            // hint text below the field.
            .onChange(of: inputText) { _, newValue in
                if newValue.contains(",") {
                    commitInput()
                }
            }
            // ⏎ commits whatever the user literally typed as a chip. We
            // intentionally DON'T auto-pick the top suggestion here —
            // pressing Enter after typing "n" was hijacking to "Save to
            // Notes" which felt like the field was overwriting input. To
            // pick a suggestion, click it (or Tab-to-complete in a later pass).
            .onSubmit {
                commitInput()
            }
            // Backspace at empty field removes the previous chip — standard
            // chip-input keyboard convention (Mail, Notion, Slack).
            .onKeyPress(.delete) {
                if inputText.isEmpty && !tokens.isEmpty {
                    tokens.removeLast()
                    return .handled
                }
                return .ignored
            }
    }

    // MARK: - Autocomplete dropdown

    private var suggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.prefix(Self.maxSuggestions)), id: \.self) { name in
                SuggestionRow(
                    name: name,
                    icon: iconForName(name),
                    onTap: { selectSuggestion(name) }
                )
            }
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    // MARK: - Suggestion filtering

    private var suggestions: [String] {
        let q = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        let alreadyUsed = Set(tokens.map { $0.lowercased() })
        return availableNames
            .filter { !alreadyUsed.contains($0.lowercased()) }
            .filter { name in
                guard !q.isEmpty else { return true }  // show all on bare focus
                // Word-prefix match — mirrors `anyWordHasPrefix` used in the
                // action list filter so users get familiar matching behavior.
                let words = name.lowercased().split(separator: " ")
                return words.contains { $0.hasPrefix(q) }
            }
            .sorted()
    }

    // MARK: - Mutation helpers

    private func commitInput() {
        let trimmed = inputText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputText = ""
            return
        }
        // Case-insensitive dedupe so "send to slack" and "Send to Slack"
        // can't both end up in the chain.
        guard !tokens.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            inputText = ""
            return
        }
        tokens.append(trimmed)
        inputText = ""
    }

    private func selectSuggestion(_ name: String) {
        guard !tokens.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            inputText = ""
            return
        }
        tokens.append(name)
        inputText = ""
        // Keep focus so the user can immediately add another step without
        // re-clicking the field — matches Mail's "To:" behavior.
        fieldIsFocused = true
    }

    private func remove(_ token: String) {
        tokens.removeAll { $0.caseInsensitiveCompare(token) == .orderedSame }
    }

    // MARK: - Type hint icon
    //
    // Best-effort — the chip input only knows names, not types. We pick a
    // generic icon ("link") for now; once chain-type metadata is surfaced
    // upstream we can map shortcut/destination per-icon.
    private func iconForName(_ name: String) -> String {
        "link"
    }
}

// MARK: - Suggestion row (separate to scope its own hover state)

private struct SuggestionRow: View {
    let name: String
    let icon: String
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.caiPrimary)
                Text(name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isHovered ? Color.caiPrimary.opacity(0.10) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// FlowLayout is defined in `MCPFormView.swift` and shared here.
// Same wrapping behavior used by the MCP form for multiselect chips.
