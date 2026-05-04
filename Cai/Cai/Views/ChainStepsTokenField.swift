import AppKit
import SwiftUI

/// SwiftUI-native chip editor for `[ChainStep]` — supports three step types:
/// Cai actions (named), inline LLM directives, and Apple Shortcuts (named).
///
/// **Design (locked 2026-05-04 evening):**
/// - Notion-style sectioned dropdown: "CAI ACTIONS" / "APPLE SHORTCUTS" /
///   "INLINE LLM STEP" — visible on focus, filters live as the user types.
/// - Distinct chip rendering per step type:
///   - `.action` — `link` SF Symbol, name in regular weight
///   - `.inlineLLM` — `sparkles` SF Symbol, **italic** truncated directive
///   - `.appleShortcut` — actual Shortcuts.app icon, name in regular weight
/// - Keyboard nav: ↑/↓ moves selection through all visible suggestions
///   (skipping section headers), ⏎ picks the highlighted item, Esc closes.
/// - Inline LLM chip: tap to open `InlineLLMEditPopover` for editing the
///   directive. Empty directive on commit → chip auto-removes (matches NSTokenField
///   convention; less friction than blocking save).
/// - Apple Shortcuts list: re-fetched on every focus (no persistent cache).
///   Cheap enough (~50-200ms) and avoids stale-data edge cases when the user
///   creates a new Shortcut and immediately returns to Cai.
///
/// **Visual language:** chips inherit `DestinationChip`'s vocabulary —
/// `caiPrimary.opacity(0.12)` fill, 5pt corner radius, 11pt medium label.
/// Per-type icon is the only visual difference between step types so the
/// overall chain reads as one rhythm.
///
/// Type name kept as `ChainStepsTokenField` (legacy from the v1.6 NSTokenField
/// experiment) to minimize project churn. Internally it's a pure SwiftUI
/// chip editor.
struct ChainStepsTokenField: View {
    @Binding var steps: [ChainStep]
    /// Pool of Cai action names available for autocomplete (the union of
    /// shortcut + destination names visible to the user, excluding the one
    /// being edited to prevent immediate self-cycle suggestions).
    let availableCaiActionNames: [String]
    let placeholder: String

    @State private var inputText: String = ""
    @State private var appleShortcuts: [String] = []
    @State private var selectedIndex: Int = 0
    /// Index into `steps` of the chip whose inline-LLM popover is open.
    /// nil when no popover is open.
    @State private var editingStepIndex: Int?
    @State private var editingDraftDirective: String = ""
    @FocusState private var fieldIsFocused: Bool

    /// Cap on dropdown rows per section (after filtering). Keeps the popover
    /// scannable on machines with many shortcuts/Apple Shortcuts.
    private static let maxRowsPerSection = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            chipRow
            if fieldIsFocused {
                suggestionsDropdown
            }
        }
    }

    // MARK: - Chip row (chips + inline TextField)

    private var chipRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                chip(for: step, at: index)
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
        .contentShape(Rectangle())
        .onTapGesture { fieldIsFocused = true }
    }

    @ViewBuilder
    private func chip(for step: ChainStep, at index: Int) -> some View {
        switch step {
        case .action(let name):
            chipShell {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.caiPrimary)
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.caiTextPrimary)
                        .lineLimit(1)
                    removeButton(at: index, label: name)
                }
            }

        case .inlineLLM(let directive):
            chipShell {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.caiPrimary)
                    Text(truncate(directive, max: 30))
                        .font(.system(size: 11, weight: .medium).italic())
                        .foregroundColor(.caiTextPrimary)
                        .lineLimit(1)
                    removeButton(at: index, label: "inline LLM step")
                }
            }
            .help(directive)
            .onTapGesture {
                editingDraftDirective = directive
                editingStepIndex = index
            }
            .popover(
                isPresented: Binding(
                    get: { editingStepIndex == index },
                    set: { if !$0 { commitInlineLLMEdit() } }
                ),
                arrowEdge: .top
            ) {
                InlineLLMEditPopover(
                    directive: $editingDraftDirective,
                    onCommit: commitInlineLLMEdit,
                    onCancel: cancelInlineLLMEdit
                )
            }

        case .appleShortcut(let name):
            chipShell {
                HStack(spacing: 4) {
                    Image(nsImage: AppleShortcutsService.appIcon)
                        .resizable()
                        .frame(width: 12, height: 12)
                    Text(name)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.caiTextPrimary)
                        .lineLimit(1)
                    removeButton(at: index, label: name)
                }
            }
        }
    }

    private func chipShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
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

    private func removeButton(at index: Int, label: String) -> some View {
        Button(action: { remove(at: index) }) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.caiTextSecondary.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help("Remove \(label)")
    }

    private var inputField: some View {
        TextField(steps.isEmpty ? placeholder : "", text: $inputText)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($fieldIsFocused)
            .frame(minWidth: 100)
            // Reset selection to top whenever the filter changes — otherwise
            // keyboard nav lands on a now-out-of-range index.
            .onChange(of: inputText) { _, _ in selectedIndex = 0 }
            // ↑/↓ navigate the dropdown.
            .onKeyPress(.upArrow) {
                let count = flatVisibleItems.count
                guard count > 0 else { return .ignored }
                selectedIndex = (selectedIndex - 1 + count) % count
                return .handled
            }
            .onKeyPress(.downArrow) {
                let count = flatVisibleItems.count
                guard count > 0 else { return .ignored }
                selectedIndex = (selectedIndex + 1) % count
                return .handled
            }
            // Enter picks the highlighted suggestion (or commits typed text
            // as inline LLM if nothing is selected).
            .onSubmit { pickHighlighted() }
            // Esc closes the dropdown.
            .onKeyPress(.escape) {
                if fieldIsFocused {
                    fieldIsFocused = false
                    return .handled
                }
                return .ignored
            }
            // Backspace at empty field removes the previous chip.
            .onKeyPress(.delete) {
                if inputText.isEmpty && !steps.isEmpty {
                    steps.removeLast()
                    return .handled
                }
                return .ignored
            }
            .onChange(of: fieldIsFocused) { _, isFocused in
                guard isFocused else { return }
                // Re-fetch Apple Shortcuts on every focus per the locked
                // design (no persistent cache). Cheap; avoids stale data.
                Task {
                    appleShortcuts = await AppleShortcutsService.shared.list()
                }
            }
    }

    // MARK: - Suggestions dropdown

    private var suggestionsDropdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleSections.enumerated()), id: \.offset) { sectionIndex, section in
                if sectionIndex > 0 {
                    Divider().padding(.vertical, 2)
                }
                sectionHeader(section.title)
                ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                    let flatIndex = flatVisibleItems.firstIndex { $0 == item } ?? -1
                    DropdownRow(
                        item: item,
                        isSelected: flatIndex == selectedIndex,
                        onTap: { pick(item) }
                    )
                }
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

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundColor(.caiTextSecondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Suggestion data model

    /// Anything the user can pick from the dropdown.
    fileprivate enum DropdownItem: Equatable, Hashable {
        case caiAction(name: String)
        case appleShortcut(name: String)
        /// "+ Inline LLM step" — directive defaults to whatever's typed.
        case inlineLLM(initialDirective: String)
    }

    fileprivate struct DropdownSection {
        let title: String
        let items: [DropdownItem]
    }

    /// The dropdown's sections in display order, with each section's items
    /// already filtered against `inputText` and the current `steps` list.
    private var visibleSections: [DropdownSection] {
        var sections: [DropdownSection] = []

        let cai = filteredCaiActions
        if !cai.isEmpty {
            sections.append(DropdownSection(title: "Cai Actions", items: cai))
        }

        let shortcuts = filteredAppleShortcuts
        if !shortcuts.isEmpty {
            sections.append(DropdownSection(title: "Apple Shortcuts", items: shortcuts))
        }

        // Inline LLM is always offered — bottom of the dropdown.
        sections.append(DropdownSection(
            title: "Add a custom step",
            items: [.inlineLLM(initialDirective: inputText.trimmingCharacters(in: .whitespaces))]
        ))

        return sections
    }

    /// Flat list of selectable items in display order — used by ↑↓ keyboard
    /// nav (which doesn't care about section boundaries).
    private var flatVisibleItems: [DropdownItem] {
        visibleSections.flatMap { $0.items }
    }

    private var filteredCaiActions: [DropdownItem] {
        let q = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        let alreadyUsed = Set(steps.compactMap { step -> String? in
            if case .action(let name) = step { return name.lowercased() }
            return nil
        })
        return availableCaiActionNames
            .filter { !alreadyUsed.contains($0.lowercased()) }
            .filter { matches($0, query: q) }
            .prefix(Self.maxRowsPerSection)
            .map { .caiAction(name: $0) }
    }

    private var filteredAppleShortcuts: [DropdownItem] {
        let q = inputText.trimmingCharacters(in: .whitespaces).lowercased()
        let alreadyUsed = Set(steps.compactMap { step -> String? in
            if case .appleShortcut(let name) = step { return name.lowercased() }
            return nil
        })
        return appleShortcuts
            .filter { !alreadyUsed.contains($0.lowercased()) }
            .filter { matches($0, query: q) }
            .prefix(Self.maxRowsPerSection)
            .map { .appleShortcut(name: $0) }
    }

    /// Word-prefix match — same matcher as the action-list filter
    /// (`anyWordHasPrefix`) so users get familiar matching behavior.
    /// Empty query matches all.
    private func matches(_ name: String, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let words = name.lowercased().split(separator: " ")
        return words.contains { $0.hasPrefix(query) }
    }

    // MARK: - Pick / commit

    private func pickHighlighted() {
        guard selectedIndex >= 0, selectedIndex < flatVisibleItems.count else {
            // No selection (or empty dropdown) → commit typed text as inline LLM
            // if there's any. Otherwise no-op.
            let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pick(.inlineLLM(initialDirective: trimmed))
            }
            return
        }
        pick(flatVisibleItems[selectedIndex])
    }

    private func pick(_ item: DropdownItem) {
        switch item {
        case .caiAction(let name):
            steps.append(.action(name: name))
            inputText = ""
        case .appleShortcut(let name):
            steps.append(.appleShortcut(name: name))
            inputText = ""
        case .inlineLLM(let initialDirective):
            // Add the chip + open the popover for editing. If user dismisses
            // without typing, the chip auto-removes on dismiss.
            steps.append(.inlineLLM(directive: initialDirective))
            inputText = ""
            editingDraftDirective = initialDirective
            editingStepIndex = steps.count - 1
        }
        selectedIndex = 0
        // Keep focus so the user can immediately add another step.
        fieldIsFocused = true
    }

    private func remove(at index: Int) {
        guard index >= 0, index < steps.count else { return }
        steps.remove(at: index)
    }

    // MARK: - Inline LLM popover lifecycle

    private func commitInlineLLMEdit() {
        guard let index = editingStepIndex, index >= 0, index < steps.count else {
            editingStepIndex = nil
            return
        }
        let trimmed = editingDraftDirective.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            // Auto-remove empty inline LLM chips — friction-free.
            steps.remove(at: index)
        } else {
            steps[index] = .inlineLLM(directive: trimmed)
        }
        editingStepIndex = nil
        editingDraftDirective = ""
    }

    private func cancelInlineLLMEdit() {
        // If the chip was just added (empty directive at construction), and
        // the user cancels, remove the chip. If they had a prior non-empty
        // directive (editing existing), preserve it.
        guard let index = editingStepIndex, index >= 0, index < steps.count else {
            editingStepIndex = nil
            editingDraftDirective = ""
            return
        }
        if case .inlineLLM(let existing) = steps[index],
           existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            steps.remove(at: index)
        }
        editingStepIndex = nil
        editingDraftDirective = ""
    }

    // MARK: - Helpers

    private func truncate(_ text: String, max: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > max else { return trimmed.isEmpty ? "(empty)" : trimmed }
        return String(trimmed.prefix(max - 1)) + "…"
    }
}

// MARK: - Dropdown row (separate view to scope its hover state)

private struct DropdownRow: View {
    let item: ChainStepsTokenField.DropdownItem
    let isSelected: Bool
    let onTap: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                icon
                    .frame(width: 14, height: 14)
                label
                Spacer(minLength: 0)
                if case .inlineLLM(let directive) = item, !directive.isEmpty {
                    // Show preview of the typed text on the right
                    Text("\u{201C}\(directive)\u{201D}")
                        .font(.system(size: 10).italic())
                        .foregroundColor(.caiTextSecondary.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(rowBackground)
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

    @ViewBuilder
    private var icon: some View {
        switch item {
        case .caiAction:
            Image(systemName: "link")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.caiPrimary)
        case .appleShortcut:
            Image(nsImage: AppleShortcutsService.appIcon)
                .resizable()
        case .inlineLLM:
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.caiPrimary)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch item {
        case .caiAction(let name), .appleShortcut(let name):
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.caiTextPrimary)
        case .inlineLLM(let directive):
            Text(directive.isEmpty ? "Inline LLM step" : "Use as prompt")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.caiTextPrimary)
        }
    }

    private var rowBackground: Color {
        if isSelected { return Color.caiPrimary.opacity(0.15) }
        if isHovered { return Color.caiPrimary.opacity(0.08) }
        return Color.clear
    }
}
