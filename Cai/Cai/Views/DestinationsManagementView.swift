import SwiftUI

/// CRUD view for managing output destinations.
/// Built-in destinations (Replace Selection, Email, Notes, Reminders) have
/// enable/disable toggles. Custom destinations support full create/edit/
/// delete with type-specific config.
///
/// **Tabbed layout (2026-05-05):** mirrors `ActionsManagementView` — top
/// segmented bar splits Built-in (toggle-only rows) from Custom (full CRUD
/// + inline edit form). The form (when editing/adding) only renders inside
/// the Custom tab.
struct DestinationsManagementView: View {
    @ObservedObject var settings = CaiSettings.shared
    let onBack: () -> Void
    var onBrowseExtensions: (() -> Void)?

    enum Tab: Hashable { case builtIn, custom }
    @State private var selectedTab: Tab = .custom

    @State private var editingDestinationId: UUID?
    @State private var isAddingNew: Bool = false
    @State private var hoveredDestinationId: UUID?

    // Form fields
    @State private var formName: String = ""
    @State private var formTypeTag: String = "webhook"
    @State private var formShowInActionList: Bool = false
    /// Chain steps to run after this destination's side-effect. Edited via
    /// the `ChainStepsTokenField` chip editor — supports Cai actions (named),
    /// inline LLM directives, and Apple Shortcuts.
    @State private var formNext: [ChainStep] = []

    /// Pool of names available for chain autocomplete. All custom shortcuts +
    /// all output destinations except the one being edited (chaining to self
    /// is a cycle the executor would catch, but suggesting it is misleading).
    private func availableChainNames(excluding excludeId: UUID?) -> [String] {
        let shortcutNames = settings.shortcuts.map(\.name)
        let destinationNames = settings.outputDestinations
            .filter { $0.id != excludeId }
            .map(\.name)
        return shortcutNames + destinationNames
    }

    // AppleScript
    @State private var formAppleScript: String = ""

    // Webhook
    @State private var formWebhookURL: String = ""
    @State private var formWebhookMethod: String = "POST"
    @State private var formWebhookHeaders: String = "{\"Content-Type\": \"application/json\"}"
    @State private var formWebhookBody: String = ""

    // Deeplink
    @State private var formDeeplink: String = ""

    // Shell
    @State private var formShellCommand: String = ""

    // Setup fields
    @State private var formSetupFields: [SetupField] = []

    // Pin to top (Custom tab only — built-in destinations stay in fixed order)
    @State private var formPinned: Bool = false

    /// Whether the "Then run" chip editor is expanded inline. Auto-set to
    /// `true` when entering edit mode on a destination with non-empty
    /// `next`. Mirrors `ShortcutsManagementView.thenRunExpanded`.
    @State private var thenRunExpandedDest: Bool = false

    /// Which form field's `(?)` help popover is open (nil = none).
    @State private var openHelpPopoverDest: HelpFieldDest?

    enum HelpFieldDest: String, Identifiable {
        case webhook, applescript, deeplink, shell, setupFields
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            screenHeader
            Divider().background(Color.caiDivider)

            TabBar(
                selection: $selectedTab,
                tabs: [
                    .init(id: .custom, label: "Custom", count: customCount),
                    .init(id: .builtIn, label: "Built-in", count: enabledBuiltInCount)
                ]
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Content
            // ScrollViewReader lets us auto-scroll the editing/adding form into
            // view so the screen doesn't appear to "jump" when content below
            // the fold expands. Mirrors ShortcutsManagementView's pattern.
            ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    switch selectedTab {
                    case .builtIn:
                        builtInTabContent
                    case .custom:
                        customTabContent
                    }
                }
                .padding(.vertical, 8)
            }
            // Auto-scroll when entering add or edit mode so the form
            // doesn't render below the fold and require manual scroll.
            // Animated to match the form's open transition.
            .onChange(of: isAddingNew) { _, isAdding in
                guard isAdding else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo("addNewDestination", anchor: .top)
                }
            }
            .onChange(of: editingDestinationId) { _, newId in
                guard let id = newId else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
            }  // end ScrollViewReader
            Spacer(minLength: 0)

            Divider()
                .background(Color.caiDivider)

            // Footer
            HStack {
                KeyboardHint(key: "Esc", label: "Back")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .onAppear {
            WindowController.acceptsFilterInput = false
        }
    }

    // MARK: - Header

    private var screenHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "paperplane.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.caiPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Destinations")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.caiTextPrimary)

                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.caiTextSecondary)
            }

            Spacer()

            // `+` only on the Custom tab — built-in destinations can't be
            // added by the user. Always visible (even while editing) — same
            // policy as ShortcutsManagementView.
            if selectedTab == .custom {
                Button(action: {
                    cancelForm()
                    resetForm()
                    WindowController.passThrough = true
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isAddingNew = true
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.caiPrimary)
                }
                .buttonStyle(.plain)
                .help("Add a new destination")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var customCount: Int {
        settings.outputDestinations.filter { !$0.isBuiltIn }.count
    }

    private var enabledBuiltInCount: Int {
        settings.outputDestinations.filter { $0.isBuiltIn && $0.isEnabled }.count
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .custom:
            return customCount == 0
                ? "Webhooks, AppleScript, deeplinks, shell"
                : "\(customCount) custom destination\(customCount == 1 ? "" : "s")"
        case .builtIn:
            let total = settings.outputDestinations.filter { $0.isBuiltIn }.count
            return "\(enabledBuiltInCount) of \(total) enabled"
        }
    }

    // MARK: - Tab Content

    /// Built-in destinations — toggle-only rows (Replace Selection, Email,
    /// Notes, Reminders). Pinned-first ordering since pin applies uniformly
    /// across both tabs.
    private var builtInTabContent: some View {
        VStack(spacing: 4) {
            ForEach(settings.outputDestinations.filter { $0.isBuiltIn }) { dest in
                builtInRow(dest)
            }

            if settings.outputDestinations.contains(where: { $0.isBuiltIn && $0.isEnabled }) {
                Text("macOS will ask for Automation permission on first use. If denied, re-enable in System Settings → Automation.")
                    .font(.system(size: 10))
                    .foregroundColor(.caiTextSecondary.opacity(0.5))
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
        }
    }

    /// Custom destinations — pinned-first ordering, click-anywhere row, full
    /// CRUD, inline edit form, browse-extensions affordance at the top
    /// (matches ActionsManagementView Custom tab for visual consistency).
    private var customTabContent: some View {
        VStack(spacing: 4) {
            // Browse extensions at the top (matches Custom Actions tab).
            if onBrowseExtensions != nil && !customDestinations.isEmpty && !isAddingNew && editingDestinationId == nil {
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
                .padding(.horizontal, 8)
            }

            ForEach(customDestinations) { dest in
                if editingDestinationId == dest.id {
                    destinationForm(isNew: false, destinationId: dest.id)
                        .id(dest.id)  // ScrollViewReader anchor for editing
                } else {
                    customRow(dest)
                }
            }

            // Add form
            if isAddingNew {
                destinationForm(isNew: true, destinationId: nil)
                    .id("addNewDestination")
            }

            // Empty state
            if customDestinations.isEmpty && !isAddingNew {
                VStack(spacing: 8) {
                    Text("No custom destinations yet")
                        .font(.system(size: 11))
                        .foregroundColor(.caiTextSecondary.opacity(0.5))

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
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
    }

    /// Custom destinations ordered pinned-first (mirrors `CaiShortcut`
    /// ordering for action-list consistency).
    private var customDestinations: [OutputDestination] {
        let custom = settings.outputDestinations.filter { !$0.isBuiltIn }
        return custom.filter(\.pinned) + custom.filter { !$0.pinned }
    }

    // MARK: - Built-in Row

    private func builtInRow(_ dest: OutputDestination) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.caiSurface.opacity(0.6))
                    .frame(width: 28, height: 28)

                Image(systemName: dest.icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.caiPrimary)
            }

            Text(dest.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.caiTextPrimary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { dest.isEnabled },
                set: { newValue in
                    if let index = settings.outputDestinations.firstIndex(where: { $0.id == dest.id }) {
                        settings.outputDestinations[index].isEnabled = newValue
                    }
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Custom Row

    /// Custom destination row — mirrors `shortcutRow` design language.
    /// Click anywhere on the row to enter edit mode (no separate edit
    /// button). Pin pattern: leading icon doubles as a pin toggle on hover
    /// for unpinned items. Share/delete moved into the editor's `⋯` menu;
    /// this row is for click-to-edit only.
    private func customRow(_ dest: OutputDestination) -> some View {
        let isHovered = hoveredDestinationId == dest.id
        let showPinIcon = dest.pinned || isHovered

        return HStack(spacing: 12) {
            // Leading icon — doubles as pin toggle on hover.
            Button(action: { togglePinDestination(dest) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(dest.pinned
                              ? Color.caiPrimary.opacity(0.15)
                              : Color.caiSurface.opacity(0.6))
                        .frame(width: 28, height: 28)

                    if showPinIcon {
                        Image(systemName: dest.pinned ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(dest.pinned
                                             ? .caiPrimary
                                             : .caiTextSecondary.opacity(0.5))
                    } else {
                        Image(systemName: dest.icon)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.caiPrimary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(dest.pinned ? "Unpin" : "Pin to top")

            // Name + type
            VStack(alignment: .leading, spacing: 1) {
                Text(dest.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.caiTextPrimary)

                Text(dest.type.label)
                    .font(.system(size: 11))
                    .foregroundColor(.caiTextSecondary)
            }

            Spacer()

            if !dest.isConfigured {
                Text("Setup needed")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.caiError)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.caiError.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.caiSurface.opacity(0.4) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            loadFormFromDestination(dest)
            WindowController.passThrough = true
            editingDestinationId = dest.id
        }
        .onHover { hovering in
            hoveredDestinationId = hovering ? dest.id : nil
        }
    }

    /// Pin/unpin a custom destination. Maintains the pinned-first
    /// invariant by re-sorting so a row visually moves on toggle.
    private func togglePinDestination(_ dest: OutputDestination) {
        guard let index = settings.outputDestinations.firstIndex(where: { $0.id == dest.id }) else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            var copy = settings.outputDestinations
            copy[index].pinned.toggle()
            // Pinned-first within the custom group; built-in stays first
            // overall (separate tab now).
            let builtIns = copy.filter(\.isBuiltIn)
            let custom = copy.filter { !$0.isBuiltIn }
            settings.outputDestinations = builtIns
                + custom.filter(\.pinned)
                + custom.filter { !$0.pinned }
        }
    }

    // MARK: - Form

    /// Destination edit/create form — Linear/Apple-inspired layout, mirrors
    /// the Custom Actions form: H1 click-to-edit title, leading pin, ⋯ menu
    /// + × close top-right, type picker (no label), per-type fields with
    /// (?) inline help popovers, inline shell/AppleScript warnings,
    /// setup-fields list (kept — they're config data, not chrome), bottom
    /// chip row (Show in action list / Then run), Save/Cancel bottom-right.
    /// Decisions live in DESIGN.md "Decisions Log" 2026-05-05.
    private func destinationForm(isNew: Bool, destinationId: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            destTitleRow(isNew: isNew, destinationId: destinationId)

            destTypePicker

            destValueFields

            setupFieldsSection

            Divider().padding(.vertical, 2)

            destChipRow(destinationId: destinationId)

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel") { cancelForm() }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    .font(.system(size: 12))
                    .foregroundColor(.caiTextSecondary)

                Button(action: {
                    saveForm(isNew: isNew, destinationId: destinationId)
                }) {
                    Text(isNew ? "Add Destination" : "Save")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(destSaveDisabled
                                      ? Color.caiPrimary.opacity(0.4)
                                      : Color.caiPrimary)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(destSaveDisabled)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.caiSurface.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.caiDivider.opacity(0.3), lineWidth: 0.5)
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Form sub-views

    /// Shared multi-line input for all type-specific code/template fields.
    /// Auto-grows from 2 lines (default) up to 4 lines, then scrolls.
    /// Wraps `MultilineTextEditor` with the standard form-field shell.
    /// All template editors (Headers JSON, Body, AppleScript, Deeplink,
    /// Shell command) use this — single source of truth for height behavior
    /// + visual treatment.
    @ViewBuilder
    private func multilineField(text: Binding<String>, placeholder: String) -> some View {
        // Derive isNew + destinationId from existing form state so
        // callers don't need to thread them. ⌘⏎ saves the form even when
        // focus is in this field; Esc cancels. Bypasses SwiftUI's
        // `keyboardShortcut` chain (which doesn't reliably route through
        // NSTextView's responder chain).
        let id = editingDestinationId
        let isNew = isAddingNew
        let editor = MultilineTextEditor(
            text: text,
            placeholder: placeholder,
            monospaced: true,
            onCommit: { saveForm(isNew: isNew, destinationId: id) },
            onCancel: { cancelForm() }
        )
        editor
            .frame(minHeight: editor.minHeight, maxHeight: editor.maxHeight)
            .formFieldShell()
    }

    /// Title row: pin (left) + H1 placeholder + ⋯ menu + × cancel.
    @ViewBuilder
    private func destTitleRow(isNew: Bool, destinationId: UUID?) -> some View {
        HStack(spacing: 8) {
            Button(action: { formPinned.toggle() }) {
                Image(systemName: formPinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(formPinned ? .caiPrimary : .caiTextSecondary.opacity(0.5))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(formPinned ? Color.caiPrimary.opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            .help(formPinned ? "Unpin from top" : "Pin to top of action list")

            TextField("Untitled destination", text: $formName)
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.caiTextPrimary)

            Spacer()

            if !isNew, let id = destinationId {
                destOptionsMenu(destinationId: id)
            }

            Button(action: { cancelForm() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary.opacity(0.7))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("Close without saving")
        }
    }

    /// Type picker — no label. Picker IS the type selector.
    private var destTypePicker: some View {
        Picker("", selection: $formTypeTag) {
            Text("Webhook").tag("webhook")
            Text("AppleScript").tag("applescript")
            Text("Deeplink").tag("deeplink")
            Text("Shell").tag("shell")
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

    /// Type-specific fields wrapper. Each type renders its own field group
    /// with inline label + (?) help + (where applicable) inline warning.
    @ViewBuilder
    private var destValueFields: some View {
        switch formTypeTag {
        case "webhook":
            destWebhookFields
        case "applescript":
            destAppleScriptFields
        case "deeplink":
            destDeeplinkFields
        case "shell":
            destShellFields
        default:
            EmptyView()
        }
    }

    /// Webhook fields — URL/method on one row, Headers + Body below.
    @ViewBuilder
    private var destWebhookFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            // URL + method on one row
            HStack(spacing: 6) {
                Text("Endpoint")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                helpButton(field: .webhook, helpText: webhookHelpText)
                Spacer()
            }
            HStack(spacing: 8) {
                Picker("", selection: $formWebhookMethod) {
                    Text("POST").tag("POST")
                    Text("PUT").tag("PUT")
                    Text("PATCH").tag("PATCH")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 160)

                TextField("https://… or {{slack_webhook_url}}", text: $formWebhookURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .formFieldShell()
            }

            // Headers JSON
            HStack(spacing: 6) {
                Text("Headers")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                if !isWebhookHeadersValid {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.caiError)
                    Text("Invalid JSON")
                        .font(.system(size: 10))
                        .foregroundColor(.caiError)
                }
                Spacer()
            }
            multilineField(
                text: $formWebhookHeaders,
                placeholder: "{ \"Content-Type\": \"application/json\" }"
            )

            // Body template
            HStack(spacing: 6) {
                Text("Body template")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                Spacer()
            }
            multilineField(
                text: $formWebhookBody,
                placeholder: "{ \"text\": \"{{result}}\" }"
            )
        }
    }

    @ViewBuilder
    private var destAppleScriptFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("AppleScript")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                helpButton(field: .applescript, helpText: appleScriptHelpText)
                Spacer().frame(width: 4)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.caiError)
                Text("Only use scripts you trust")
                    .font(.system(size: 10))
                    .foregroundColor(.caiError)
                Spacer()
            }
            multilineField(
                text: $formAppleScript,
                placeholder: "tell application \"Notes\" to make new note with properties {body: \"{{result}}\"}"
            )
        }
    }

    @ViewBuilder
    private var destDeeplinkFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Deeplink")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                helpButton(field: .deeplink, helpText: deeplinkHelpText)
                Spacer()
            }
            multilineField(
                text: $formDeeplink,
                placeholder: "bear://x-callback-url/create?text={{result}}"
            )
        }
    }

    @ViewBuilder
    private var destShellFields: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Shell command")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                helpButton(field: .shell, helpText: shellHelpText)
                Spacer().frame(width: 4)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.caiError)
                Text("Only use commands you trust")
                    .font(.system(size: 10))
                    .foregroundColor(.caiError)
                Spacer()
            }
            multilineField(
                text: $formShellCommand,
                placeholder: "echo {{result}} | pbcopy"
            )
        }
    }

    /// Setup fields list — kept structurally (they're config data per
    /// destination, not form chrome). Visual treatment slightly tightened
    /// to match the new design language: smaller key prefix, plain inputs
    /// on `caiSurface`, eye toggle for secrets, minus to remove.
    @ViewBuilder
    private var setupFieldsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Setup fields")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)
                helpButton(field: .setupFields, helpText: setupFieldsHelpText)
                Spacer()
            }

            ForEach($formSetupFields) { $field in
                HStack(spacing: 6) {
                    HStack(spacing: 2) {
                        Text("{{")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.caiTextSecondary.opacity(0.5))
                        TextField("key", text: $field.key)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 80)
                        Text("}}")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.caiTextSecondary.opacity(0.5))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )

                    Group {
                        if field.isSecret {
                            SecureField("Value", text: $field.value)
                        } else {
                            TextField("Value", text: $field.value)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
                    )

                    Button(action: { field.isSecret.toggle() }) {
                        Image(systemName: field.isSecret ? "eye.slash.fill" : "eye")
                            .font(.system(size: 10))
                            .foregroundColor(field.isSecret ? .orange : .caiTextSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help(field.isSecret ? "Secret field (hidden)" : "Visible field")

                    Button(action: {
                        formSetupFields.removeAll { $0.id == field.id }
                    }) {
                        Image(systemName: "minus.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.caiTextSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("Remove setup field")
                }
            }

            Button(action: {
                // Default to hidden — setup fields typically hold webhook
                // URLs, API tokens, or other secrets. Safer for screen-share
                // / pair-programming. Users can click the eye to reveal.
                formSetupFields.append(SetupField(key: "", isSecret: true))
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 10))
                    Text("Add setup field")
                        .font(.system(size: 10))
                }
                .foregroundColor(.caiPrimary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Bottom chip row — Then run + Show in action list. Same chip
    /// vocabulary as Custom Actions: neutral disclosure chip for "Then
    /// run", indigo toggle chip for "Show in action list".
    @ViewBuilder
    private func destChipRow(destinationId: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ChipButton(
                    label: destThenRunLabel,
                    icon: thenRunExpandedDest || !formNext.isEmpty ? "chevron.down" : "chevron.right",
                    isActive: thenRunExpandedDest || !formNext.isEmpty,
                    tooltip: "Chain follow-up actions",
                    action: { thenRunExpandedDest.toggle() }
                )

                ChipToggle(
                    label: "Show in action list",
                    icon: "eye",
                    isOn: formShowInActionList,
                    tooltip: "Show as a direct-route chip in the result view",
                    action: { formShowInActionList.toggle() }
                )

                Spacer()
            }

            if thenRunExpandedDest || !formNext.isEmpty {
                ChainStepsTokenField(
                    steps: $formNext,
                    availableCaiActionNames: availableChainNames(excluding: destinationId),
                    placeholder: "Search actions to add..."
                )
            }
        }
    }

    private var destThenRunLabel: String {
        if formNext.isEmpty { return "Then run" }
        return "Then run · \(formNext.count)"
    }

    /// `(?)` help button — same pattern as Custom Actions.
    @ViewBuilder
    private func helpButton(field: HelpFieldDest, helpText: String) -> some View {
        Button(action: {
            openHelpPopoverDest = (openHelpPopoverDest == field) ? nil : field
        }) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.caiTextSecondary.opacity(0.5))
        }
        .buttonStyle(.plain)
        .help(helpText)
        .popover(
            isPresented: Binding(
                get: { openHelpPopoverDest == field },
                set: { if !$0 { openHelpPopoverDest = nil } }
            ),
            arrowEdge: .top
        ) {
            Text(helpText)
                .font(.system(size: 11))
                .foregroundColor(.caiTextPrimary)
                .padding(10)
                .frame(maxWidth: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var webhookHelpText: String {
        "POST/PUT/PATCH to a URL. Use {{result}} for the LLM result, {{key}} for setup-field values. The body template is sent verbatim — make sure the JSON is valid."
    }

    private var appleScriptHelpText: String {
        "Runs via osascript. Use {{result}} for the LLM result — strings are auto-escaped for AppleScript. {{key}} resolves setup fields."
    }

    private var deeplinkHelpText: String {
        "Opens a URL scheme like bear://, things://, or omnifocus://. Use {{result}} for the LLM result (auto-encoded). {{key}} resolves setup fields."
    }

    private var shellHelpText: String {
        "Runs via /bin/zsh -c. Use {{result}} for the LLM result (auto-quoted). The result is also passed via stdin."
    }

    private var setupFieldsHelpText: String {
        "Configurable values referenced by {{key}} in your URL/template/body. Webhook URLs, API tokens, channel names — anything you'd otherwise hardcode. Mark as secret to hide the value in the editor."
    }

    /// `⋯` overflow menu — Duplicate / Share as Extension / Delete.
    @ViewBuilder
    private func destOptionsMenu(destinationId: UUID) -> some View {
        Menu {
            Button(action: { duplicateDestination(destinationId: destinationId) }) {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            if let dest = settings.outputDestinations.first(where: { $0.id == destinationId }) {
                Button(action: { shareDestinationAsExtension(dest) }) {
                    Label("Share as Extension", systemImage: "square.and.arrow.up")
                }
            }
            Divider()
            Button(role: .destructive, action: { deleteDestination(destinationId: destinationId) }) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.caiTextSecondary.opacity(0.7))
                .frame(width: 24, height: 24)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24)
        .help("More options")
    }

    private var destSaveDisabled: Bool {
        formName.trimmingCharacters(in: .whitespaces).isEmpty
            || (formTypeTag == "webhook" && !isWebhookHeadersValid)
    }

    /// Duplicate the destination — copy all fields, append " (Copy)" to name,
    /// insert pinned-first within the custom group. Closes the editor.
    private func duplicateDestination(destinationId: UUID) {
        guard let original = settings.outputDestinations.first(where: { $0.id == destinationId }) else { return }
        let copy = OutputDestination(
            name: "\(original.name) (Copy)",
            icon: original.icon,
            type: original.type,
            isEnabled: true,
            isBuiltIn: false,
            showInActionList: original.showInActionList,
            setupFields: original.setupFields,
            next: original.next,
            pinned: false  // duplicates start unpinned
        )
        withAnimation(.easeInOut(duration: 0.15)) {
            var working = settings.outputDestinations
            working.append(copy)
            let builtIns = working.filter(\.isBuiltIn)
            let custom = working.filter { !$0.isBuiltIn }
            settings.outputDestinations = builtIns
                + custom.filter(\.pinned)
                + custom.filter { !$0.pinned }
        }
        cancelForm()
    }

    /// Delete the destination. Closes the editor.
    private func deleteDestination(destinationId: UUID) {
        withAnimation(.easeInOut(duration: 0.15)) {
            settings.outputDestinations.removeAll { $0.id == destinationId }
        }
        cancelForm()
    }

    // (Per-type field helpers — destAppleScriptFields, destWebhookFields,
    // destDeeplinkFields, destShellFields — live above with the redesigned
    // form, replacing the older `appleScriptFields` / `webhookFields` /
    // `deeplinkFields` / `shellFields` helpers that used TextEditor +
    // labeled hints. The new versions use TextField(axis: .vertical) for
    // multi-line auto-grow and `(?)` popovers for help.)

    // MARK: - Form Helpers

    private func buildDestinationType() -> DestinationType {
        // Normalize smart/curly quotes in template fields — macOS's smart-quote
        // autocorrect silently replaces typed quotes, and zsh, URL schemes,
        // AppleScript, and JSON webhook bodies only understand straight quotes.
        switch formTypeTag {
        case "applescript":
            return .applescript(template: formAppleScript.normalizingSmartQuotes())
        case "webhook":
            let headers = parseHeaders(formWebhookHeaders.normalizingSmartQuotes())
            return .webhook(WebhookConfig(
                url: formWebhookURL.normalizingSmartQuotes(),
                method: formWebhookMethod,
                headers: headers,
                bodyTemplate: formWebhookBody.normalizingSmartQuotes()
            ))
        case "deeplink":
            return .deeplink(template: formDeeplink.normalizingSmartQuotes())
        case "shell":
            return .shell(command: formShellCommand.normalizingSmartQuotes())
        default:
            return .webhook(WebhookConfig(url: "", bodyTemplate: ""))
        }
    }

    private func parseHeaders(_ json: String) -> [String: String] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return ["Content-Type": "application/json"]
        }
        return dict
    }

    /// Whether the webhook headers field currently contains a valid `[String: String]`
    /// JSON object (or is empty — empty falls back to the default Content-Type).
    /// Used to gate the Save button and show an inline warning. Without this gate
    /// the form would silently fall back to defaults on parse failure, which looked
    /// like a save bug from the user's perspective.
    private var isWebhookHeadersValid: Bool {
        let trimmed = formWebhookHeaders.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        let normalized = formWebhookHeaders.normalizingSmartQuotes()
        guard let data = normalized.data(using: .utf8),
              (try? JSONSerialization.jsonObject(with: data) as? [String: String]) != nil else {
            return false
        }
        return true
    }

    private func loadFormFromDestination(_ dest: OutputDestination) {
        formName = dest.name
        formShowInActionList = dest.showInActionList
        formSetupFields = dest.setupFields
        formNext = dest.next
        formPinned = dest.pinned
        // Auto-expand the chain editor if there are steps already.
        thenRunExpandedDest = !dest.next.isEmpty

        switch dest.type {
        case .applescript(let template):
            formTypeTag = "applescript"
            formAppleScript = template
        case .webhook(let config):
            formTypeTag = "webhook"
            formWebhookURL = config.url
            formWebhookMethod = config.method
            if let data = try? JSONSerialization.data(withJSONObject: config.headers, options: [.prettyPrinted]),
               let str = String(data: data, encoding: .utf8) {
                formWebhookHeaders = str
            }
            formWebhookBody = config.bodyTemplate
        case .deeplink(let template):
            formTypeTag = "deeplink"
            formDeeplink = template
        case .shell(let command):
            formTypeTag = "shell"
            formShellCommand = command
        case .pasteBack:
            // pasteBack is a built-in destination and has no editable fields.
            // Built-in rows don't render an Edit button, so this case should be
            // unreachable — assert in debug, no-op in release rather than silently
            // coercing to a webhook form.
            assertionFailure("pasteBack is a built-in destination and cannot be edited")
            return
        }
    }

    private func saveForm(isNew: Bool, destinationId: UUID?) {
        let trimmedName = formName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let destType = buildDestinationType()
        // Token field already trims and drops empties — defensive re-filter
        // Editor strips empty inline-LLM chips on commit, but defensively
        // filter again in case a programmatic update slipped past it.
        let nextSteps = formNext.filter { !$0.isEmpty }

        if isNew {
            let dest = OutputDestination(
                name: trimmedName,
                icon: iconForTypeTag(formTypeTag),
                type: destType,
                isEnabled: true,
                isBuiltIn: false,
                showInActionList: formShowInActionList,
                setupFields: formSetupFields,
                next: nextSteps,
                pinned: formPinned
            )
            withAnimation(.easeInOut(duration: 0.15)) {
                // Insert maintaining pinned-first invariant within the
                // custom group (built-in stays before custom overall).
                var working = settings.outputDestinations
                working.append(dest)
                let builtIns = working.filter(\.isBuiltIn)
                let custom = working.filter { !$0.isBuiltIn }
                settings.outputDestinations = builtIns
                    + custom.filter(\.pinned)
                    + custom.filter { !$0.pinned }
            }
        } else if let id = destinationId,
                  let index = settings.outputDestinations.firstIndex(where: { $0.id == id }) {
            withAnimation(.easeInOut(duration: 0.15)) {
                var copy = settings.outputDestinations
                copy[index].name = trimmedName
                copy[index].icon = iconForTypeTag(formTypeTag)
                copy[index].type = destType
                copy[index].showInActionList = formShowInActionList
                copy[index].setupFields = formSetupFields
                copy[index].next = nextSteps
                copy[index].pinned = formPinned
                let builtIns = copy.filter(\.isBuiltIn)
                let custom = copy.filter { !$0.isBuiltIn }
                settings.outputDestinations = builtIns
                    + custom.filter(\.pinned)
                    + custom.filter { !$0.pinned }
            }
        }

        cancelForm()
    }

    private func iconForTypeTag(_ tag: String) -> String {
        switch tag {
        case "webhook": return "arrow.up.right.square"
        case "applescript": return "applescript"
        case "deeplink": return "link"
        case "shell": return "terminal"
        default: return "arrow.up.right.square"
        }
    }

    private func resetForm() {
        formName = ""
        formTypeTag = "webhook"
        formShowInActionList = false
        formAppleScript = ""
        formWebhookURL = ""
        formWebhookMethod = "POST"
        formWebhookHeaders = "{\"Content-Type\": \"application/json\"}"
        formWebhookBody = ""
        formDeeplink = ""
        formShellCommand = ""
        formSetupFields = []
        formNext = []
        formPinned = false
        thenRunExpandedDest = false
        openHelpPopoverDest = nil
    }

    private func cancelForm() {
        WindowController.passThrough = false
        withAnimation(.easeInOut(duration: 0.15)) {
            isAddingNew = false
            editingDestinationId = nil
        }
        // Defer the form @State reset by one runloop tick. The form contains
        // `ForEach($formSetupFields)` whose row TextFields commit on blur via
        // index-based bindings (`$formSetupFields[N].value`). If we clear
        // `formSetupFields` synchronously here, an in-flight commit triggered
        // by the teardown layout pass will index into an empty array and trap
        // (`Swift/ContiguousArrayBuffer.swift:691: Fatal error: Index out of range`).
        // Deferring lets SwiftUI detach the TextFields first; by next tick the
        // bindings are gone and clearing the array is safe.
        // Repro: open a webhook destination, type into a setup field's value,
        // click Save while focus is still in the field — pre-fix this crashes.
        DispatchQueue.main.async {
            self.resetForm()
        }
    }

    // MARK: - Share as Extension

    private func shareDestinationAsExtension(_ dest: OutputDestination) {
        var yaml = """
            # cai-extension
            name: \(dest.name)
            description: \(dest.name)
            author: your-github-username
            version: "1.0"
            tags: []
            icon: \(dest.icon)
            """

        switch dest.type {
        case .webhook(let config):
            yaml += "\ntype: webhook"
            yaml += "\nshow_in_action_list: \(dest.showInActionList)"
            yaml += "\nwebhook:"
            yaml += "\n  url: \"\(config.url)\""
            yaml += "\n  method: \(config.method)"
            if !config.headers.isEmpty {
                yaml += "\n  headers:"
                for (key, value) in config.headers {
                    yaml += "\n    \(key): \(value)"
                }
            }
            yaml += "\n  body: '\(config.bodyTemplate)'"

        case .deeplink(let template):
            yaml += "\ntype: deeplink"
            yaml += "\nshow_in_action_list: \(dest.showInActionList)"
            yaml += "\ndeeplink: \"\(template)\""

        case .shell(let command):
            let indented = command.components(separatedBy: "\n")
                .map { "  \($0)" }.joined(separator: "\n")
            yaml += "\ntype: shell"
            yaml += "\ncommand: |\n\(indented)"

        case .applescript(let template):
            let indented = template.components(separatedBy: "\n")
                .map { "  \($0)" }.joined(separator: "\n")
            yaml += "\ntype: applescript"
            yaml += "\napplescript: |\n\(indented)"

        case .pasteBack:
            // pasteBack is built-in only; not shareable as an extension.
            return
        }

        // Setup fields
        if !dest.setupFields.isEmpty {
            yaml += "\nsetup:"
            for field in dest.setupFields {
                yaml += "\n  - key: \(field.key)"
                yaml += "\n    label: \(field.key)"
                yaml += "\n    secret: \(field.isSecret)"
            }
        }

        yaml += "\n"

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
