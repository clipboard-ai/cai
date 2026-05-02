import SwiftUI

/// Management screen for creating, editing, and deleting custom shortcuts.
/// Follows the same layout pattern as ClipboardHistoryView: header, scrollable
/// list, footer with keyboard hints.
struct ShortcutsManagementView: View {
    @ObservedObject var settings = CaiSettings.shared
    let onBack: () -> Void
    var onBrowseExtensions: (() -> Void)?

    @State private var editingShortcutId: UUID?
    @State private var isAddingNew: Bool = false
    /// Tracks which row is hovered so the leading icon can morph into a pin
    /// affordance for unpinned shortcuts (mirrors `ClipboardHistoryView`).
    @State private var hoveredShortcutId: UUID?

    // Form fields
    @State private var formName: String = ""
    @State private var formType: CaiShortcut.ShortcutType = .prompt
    @State private var formValue: String = ""
    @State private var formAutoReplace: Bool = false
    @State private var formPinned: Bool = false

    /// Display order for the Settings list and the action list: pinned first
    /// (in user-defined drag order), unpinned after (also in user order).
    /// `settings.shortcuts` is the canonical store; this is only a view.
    private var orderedShortcuts: [CaiShortcut] {
        settings.shortcuts.filter(\.pinned) + settings.shortcuts.filter { !$0.pinned }
    }

    /// Drag-to-reorder handler. Operates on `orderedShortcuts` indices, then
    /// re-sorts so the pinned-first invariant holds: a row dragged across the
    /// pinned/unpinned boundary snaps back to the boundary on drop.
    private func moveShortcut(from source: IndexSet, to destination: Int) {
        var working = orderedShortcuts
        working.move(fromOffsets: source, toOffset: destination)
        settings.shortcuts = working.filter(\.pinned) + working.filter { !$0.pinned }
    }

    /// Toggle pin from the leading icon button. Maintains the pinned-first
    /// invariant so the row visually moves to its new section on toggle.
    private func togglePin(_ shortcut: CaiShortcut) {
        guard let index = settings.shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            var copy = settings.shortcuts
            copy[index].pinned.toggle()
            settings.shortcuts = copy.filter(\.pinned) + copy.filter { !$0.pinned }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.caiPrimary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Custom Actions")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.caiTextPrimary)

                    Text(settings.shortcuts.isEmpty
                         ? "Type to filter actions when Cai is open"
                         : "\(settings.shortcuts.count) custom action\(settings.shortcuts.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.caiTextSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(Color.caiDivider)

            // Content — `List` (not `ScrollView { VStack }`) so `.onMove` can wire
            // up drag-to-reorder. `.listStyle(.plain)` + per-row clear background
            // strips List's default chrome so rows keep their card aesthetic.
            List {
                if settings.shortcuts.isEmpty && !isAddingNew {
                    emptyState
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } else {
                    ForEach(orderedShortcuts) { shortcut in
                        Group {
                            if editingShortcutId == shortcut.id {
                                shortcutForm(isNew: false, shortcutId: shortcut.id)
                            } else {
                                shortcutRow(shortcut)
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    }
                    .onMove(perform: moveShortcut)

                    if isAddingNew {
                        shortcutForm(isNew: true, shortcutId: nil)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
                    }
                }

                // Add button (when not already adding)
                if !isAddingNew && editingShortcutId == nil {
                    Button(action: {
                        formName = ""
                        formType = .prompt
                        formValue = ""
                        formAutoReplace = false
                        formPinned = false
                        isAddingNew = true
                        WindowController.passThrough = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                            Text("Add Action")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.caiPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.caiPrimary.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }

                // Browse community extensions — always visible, so users can
                // discover new actions without having to empty their own list first.
                if onBrowseExtensions != nil && !settings.shortcuts.isEmpty && !isAddingNew && editingShortcutId == nil {
                    Button(action: { onBrowseExtensions?() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 10, weight: .medium))
                            Text("Browse Community Extensions")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.caiPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            Divider()
                .background(Color.caiDivider)

            // Footer
            HStack(spacing: 12) {
                KeyboardHint(key: "Esc", label: "Back")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bolt.circle")
                .font(.system(size: 28))
                .foregroundColor(.caiTextSecondary.opacity(0.4))
            Text("No custom actions yet")
                .font(.system(size: 13))
                .foregroundColor(.caiTextSecondary)
            Text("Create custom actions for prompts you use often\nor URLs you search frequently")
                .font(.system(size: 11))
                .foregroundColor(.caiTextSecondary.opacity(0.6))
                .multilineTextAlignment(.center)

            if onBrowseExtensions != nil {
                Button(action: { onBrowseExtensions?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10, weight: .medium))
                        Text("Browse Community Extensions")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.caiPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 80)
        .padding()
    }

    // MARK: - Shortcut Row

    private func shortcutRow(_ shortcut: CaiShortcut) -> some View {
        let isHovered = hoveredShortcutId == shortcut.id
        // Show the pin glyph when pinned (always) or hovered (progressive disclosure
        // for unpinned rows — same pattern as `ClipboardHistoryView.historyRow`).
        let showPinIcon = shortcut.pinned || isHovered

        return HStack(spacing: 12) {
            // Leading icon — doubles as pin toggle on hover.
            Button(action: { togglePin(shortcut) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(shortcut.pinned
                              ? Color.caiPrimary.opacity(0.15)
                              : Color.caiSurface.opacity(0.6))
                        .frame(width: 28, height: 28)

                    if showPinIcon {
                        Image(systemName: shortcut.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(shortcut.pinned
                                             ? .caiPrimary
                                             : .caiTextSecondary.opacity(0.5))
                    } else {
                        Image(systemName: shortcut.type.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.caiTextSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(shortcut.pinned ? "Unpin" : "Pin to top")

            // Name + value preview
            VStack(alignment: .leading, spacing: 1) {
                Text(shortcut.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.caiTextPrimary)

                Text(shortcut.value)
                    .font(.system(size: 11))
                    .foregroundColor(.caiTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Share as extension
            Button(action: {
                shareShortcutAsExtension(shortcut)
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary.opacity(0.6))
                    .padding(4)
            }
            .buttonStyle(.plain)

            // Edit button
            Button(action: {
                formName = shortcut.name
                formType = shortcut.type
                formValue = shortcut.value
                formAutoReplace = shortcut.autoReplaceSelection
                formPinned = shortcut.pinned
                editingShortcutId = shortcut.id
                WindowController.passThrough = true
            }) {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary.opacity(0.6))
                    .padding(4)
            }
            .buttonStyle(.plain)

            // Delete button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.15)) {
                    settings.shortcuts.removeAll { $0.id == shortcut.id }
                }
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary.opacity(0.6))
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredShortcutId = hovering ? shortcut.id : nil
        }
    }

    // MARK: - Shortcut Form (Add / Edit)

    private func shortcutForm(isNew: Bool, shortcutId: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Name field
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                TextField("e.g. Email Reply, Reddit", text: $formName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
            }

            // Type picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Type")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                Picker("", selection: $formType) {
                    ForEach(CaiShortcut.ShortcutType.allCases, id: \.self) { type in
                        Text(type.label).tag(type)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Value field
            VStack(alignment: .leading, spacing: 4) {
                let fieldLabel: String = {
                    switch formType {
                    case .prompt: return "Prompt"
                    case .url: return "URL Template"
                    case .shell: return "Shell Command"
                    }
                }()
                Text(fieldLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                let useMonospaced = formType == .url || formType == .shell
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $formValue)
                        .font(.system(size: 12, design: useMonospaced ? .monospaced : .default))
                        .scrollContentBackground(.hidden)
                        .padding(4)
                    if formValue.isEmpty {
                        Text(formType.placeholder)
                            .font(.system(size: 12, design: useMonospaced ? .monospaced : .default))
                            .foregroundColor(.caiTextSecondary.opacity(0.4))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: 60, maxHeight: 140)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(5)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                )
                if formType == .url {
                    Text("Use %s where clipboard text should be inserted")
                        .font(.system(size: 10))
                        .foregroundColor(.caiTextSecondary.opacity(0.5))
                } else if formType == .shell {
                    Text("Use {{result}} where clipboard text should be inserted. Text is also passed via stdin.")
                        .font(.system(size: 10))
                        .foregroundColor(.caiTextSecondary.opacity(0.5))
                }

                // Code execution warning
                if formType == .shell {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.caiError)
                        Text("This action will execute code on your machine. Only use commands you understand and trust.")
                            .font(.system(size: 10))
                            .foregroundColor(.caiError)
                    }
                    .padding(8)
                    .background(Color.caiError.opacity(0.08))
                    .cornerRadius(6)
                }
            }

            // Auto replace selection, prompt-type only
            if formType == .prompt {
                Toggle(isOn: $formAutoReplace) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto replace selection")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.caiTextPrimary)
                        Text("Paste the response over your selection and skip the review screen.")
                            .font(.system(size: 10))
                            .foregroundColor(.caiTextSecondary.opacity(0.6))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }

            // Pin to top — applies to all types.
            Toggle(isOn: $formPinned) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pin to top")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.caiTextPrimary)
                    Text("Show this action in the default list above the built-ins. Drag rows to reorder; pinned ones stay on top.")
                        .font(.system(size: 10))
                        .foregroundColor(.caiTextSecondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            // Save / Cancel buttons
            HStack(spacing: 8) {
                Button("Cancel") {
                    cancelForm()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.caiTextSecondary)

                Spacer()

                Button(action: {
                    saveForm(isNew: isNew, shortcutId: shortcutId)
                }) {
                    Text(isNew ? "Add" : "Save")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(formName.isEmpty || formValue.isEmpty
                                      ? Color.caiPrimary.opacity(0.4)
                                      : Color.caiPrimary)
                        )
                }
                .buttonStyle(.plain)
                .disabled(formName.isEmpty || formValue.isEmpty)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.caiSurface.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.caiDivider.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 8)
    }

    // MARK: - Form Helpers

    private func saveForm(isNew: Bool, shortcutId: UUID?) {
        let trimmedName = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Normalize smart/curly quotes to straight quotes — macOS's smart-quote
        // autocorrect silently replaces typed quotes in text fields, and zsh
        // (Shell type) + URL schemes only understand straight quotes.
        let trimmedValue = formValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .normalizingSmartQuotes()
        guard !trimmedName.isEmpty, !trimmedValue.isEmpty else { return }

        // Only the prompt type supports auto-replace; other types silently drop it.
        let autoReplace = formType == .prompt && formAutoReplace

        if isNew {
            let shortcut = CaiShortcut(
                name: trimmedName,
                type: formType,
                value: trimmedValue,
                autoReplaceSelection: autoReplace,
                pinned: formPinned
            )
            withAnimation(.easeInOut(duration: 0.15)) {
                // Build the new ordered array in a local, then assign once so
                // `shortcuts.didSet` (and the `caiInvalidateActionCache` it posts)
                // fires a single time per save.
                var copy = settings.shortcuts
                copy.append(shortcut)
                settings.shortcuts = copy.filter(\.pinned) + copy.filter { !$0.pinned }
            }
        } else if let id = shortcutId,
                  let index = settings.shortcuts.firstIndex(where: { $0.id == id }) {
            withAnimation(.easeInOut(duration: 0.15)) {
                // Mutate a working copy so the @Published didSet fires once,
                // not once per property assignment.
                var copy = settings.shortcuts
                copy[index].name = trimmedName
                copy[index].type = formType
                copy[index].value = trimmedValue
                copy[index].autoReplaceSelection = autoReplace
                copy[index].pinned = formPinned
                settings.shortcuts = copy.filter(\.pinned) + copy.filter { !$0.pinned }
            }
        }

        cancelForm()
    }

    private func cancelForm() {
        WindowController.passThrough = false
        withAnimation(.easeInOut(duration: 0.15)) {
            isAddingNew = false
            editingShortcutId = nil
        }
        formName = ""
        formType = .prompt
        formValue = ""
        formAutoReplace = false
        formPinned = false
    }

    // MARK: - Share as Extension

    private func shareShortcutAsExtension(_ shortcut: CaiShortcut) {
        var yaml = """
            # cai-extension
            name: \(shortcut.name)
            description: \(shortcut.name)
            author: your-github-username
            version: "1.0"
            tags: []
            icon: \(shortcut.type.icon)
            type: \(shortcut.type.rawValue)\n
            """

        switch shortcut.type {
        case .prompt:
            let indented = shortcut.value.components(separatedBy: "\n")
                .map { "  \($0)" }.joined(separator: "\n")
            yaml += "prompt: |\n\(indented)\n"
        case .url:
            yaml += "url: \"\(shortcut.value)\"\n"
        case .shell:
            let indented = shortcut.value.components(separatedBy: "\n")
                .map { "  \($0)" }.joined(separator: "\n")
            yaml += "command: |\n\(indented)\n"
        }

        SystemActions.copyToClipboard(yaml)

        if let url = URL(string: "https://github.com/cai-layer/cai-extensions") {
            NSWorkspace.shared.open(url)
        }

        NotificationCenter.default.post(
            name: .caiShowToast,
            object: nil,
            userInfo: ["message": "Extension YAML copied"]
        )
    }
}
