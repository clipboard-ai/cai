import SwiftUI
import MCP

/// Generic form renderer for MCP-powered actions.
/// Renders any `MCPActionConfig` into a form — text fields, pickers, multiselects —
/// driven entirely by the config. No provider-specific UI code needed.
///
/// Flow: auto-connect if needed → LLM-generate title/body → fetch picker options → user edits → submit.
struct MCPFormView: View {
    let actionConfig: MCPActionConfig
    let clipboardText: String
    let sourceApp: String?
    let onBack: () -> Void
    let onDismiss: () -> Void

    // MARK: - Form State

    /// Current field values, keyed by field id ("title", "body", "repo", etc.)
    @State private var fieldValues: [String: String] = [:]
    /// Selected options for multiselect fields, keyed by field id
    @State private var multiSelectValues: [String: Set<String>] = [:]
    /// Fetched options for picker/multiselect fields, keyed by field id
    @State private var pickerOptions: [String: [MCPPickerOption]] = [:]
    /// Loading states per field
    @State private var fieldLoading: [String: Bool] = [:]

    // MARK: - Overall State

    @State private var isConnecting: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var isGeneratingLLM: Bool = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    @FocusState private var focusedField: String?

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .background(Color.caiDivider)

            if isConnecting {
                connectingView
            } else if let success = successMessage {
                successView(success)
            } else {
                formContent
            }
        }
        .task {
            await initialize()
        }
        .onAppear {
            WindowController.passThrough = true
        }
        .onDisappear {
            WindowController.passThrough = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .caiMCPFormSubmit)) { _ in
            Task { await submit() }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 10) {
            Image(systemName: actionConfig.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.caiPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text(actionConfig.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.caiTextPrimary)

                Text(clipboardText)
                    .font(.system(size: 11))
                    .foregroundColor(.caiTextSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Connecting

    private var connectingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(0.8)
            Text("Connecting…")
                .font(.system(size: 12))
                .foregroundColor(.caiTextSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    // MARK: - Success

    private func successView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundColor(.green)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.caiTextPrimary)
                .multilineTextAlignment(.center)
            Spacer()

            KeyboardHint(key: "↩", label: "Dismiss")
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
    }

    // MARK: - Form Content

    private var formContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(actionConfig.fields) { field in
                        fieldView(for: field)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }

            Divider()
                .background(Color.caiDivider)

            footerView
        }
    }

    // MARK: - Field Rendering

    @ViewBuilder
    private func fieldView(for field: MCPFieldConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.caiTextSecondary)

                if field.required {
                    Text("*")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                }

                if fieldLoading[field.id] == true {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 12, height: 12)
                }
            }

            switch field.type {
            case .text:
                textField(for: field)
            case .textarea:
                textAreaField(for: field)
            case .picker:
                pickerField(for: field)
            case .multiselect:
                multiselectField(for: field)
            }
        }
    }

    private func textField(for field: MCPFieldConfig) -> some View {
        let binding = Binding<String>(
            get: { fieldValues[field.id] ?? "" },
            set: { fieldValues[field.id] = $0 }
        )
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.caiSurface.opacity(0.6))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.caiDivider.opacity(0.5), lineWidth: 0.5)
            TextField(field.label, text: binding)
                .font(.system(size: 13))
                .foregroundColor(.caiTextPrimary)
                .textFieldStyle(.plain)
                .padding(8)
                .focused($focusedField, equals: field.id)
        }
        .frame(height: 32)
    }

    private func textAreaField(for field: MCPFieldConfig) -> some View {
        let binding = Binding<String>(
            get: { fieldValues[field.id] ?? "" },
            set: { fieldValues[field.id] = $0 }
        )
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.caiSurface.opacity(0.6))
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.caiDivider.opacity(0.5), lineWidth: 0.5)
            TextEditor(text: binding)
                .font(.system(size: 13))
                .foregroundColor(.caiTextPrimary)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .padding(8)
                .focused($focusedField, equals: field.id)
        }
        .frame(minHeight: 80, maxHeight: 120)
    }

    private func pickerField(for field: MCPFieldConfig) -> some View {
        let options = pickerOptions[field.id] ?? []
        let binding = Binding<String>(
            get: { fieldValues[field.id] ?? "" },
            set: { fieldValues[field.id] = $0 }
        )
        return Group {
            if options.isEmpty && fieldLoading[field.id] != true {
                Text("No options available")
                    .font(.system(size: 12))
                    .foregroundColor(.caiTextSecondary)
                    .padding(.vertical, 4)
            } else {
                Picker("", selection: binding) {
                    Text("Select…").tag("")
                    ForEach(options) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private func multiselectField(for field: MCPFieldConfig) -> some View {
        let options = pickerOptions[field.id] ?? []
        let selected = multiSelectValues[field.id] ?? []

        return Group {
            if options.isEmpty && fieldLoading[field.id] != true {
                Text("No options available")
                    .font(.system(size: 12))
                    .foregroundColor(.caiTextSecondary)
                    .padding(.vertical, 4)
            } else {
                // Horizontally wrapping chips
                FlowLayout(spacing: 6) {
                    ForEach(options) { option in
                        let isSelected = selected.contains(option.id)
                        Button(action: {
                            toggleMultiSelect(field: field.id, optionId: option.id)
                        }) {
                            Text(option.label)
                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(isSelected ? .white : .caiTextPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(isSelected ? Color.caiPrimary : Color.caiSurface.opacity(0.8))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(isSelected ? Color.clear : Color.caiDivider.opacity(0.5), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func toggleMultiSelect(field: String, optionId: String) {
        var current = multiSelectValues[field] ?? []
        if current.contains(optionId) {
            current.remove(optionId)
        } else {
            current.insert(optionId)
        }
        multiSelectValues[field] = current
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            if isSubmitting {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Submitting…")
                    .font(.system(size: 11))
                    .foregroundColor(.caiTextSecondary)
            }

            Spacer()

            HStack(spacing: 12) {
                KeyboardHint(key: "Esc", label: "Back")
                KeyboardHint(key: "⌘↩", label: actionConfig.confirmLabel)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Initialization

    private func initialize() async {
        // Step 1: Ensure MCP server is connected
        guard let serverConfig = MCPConfigManager.shared.serverConfigs.first(where: { $0.id == actionConfig.serverConfigId }) else {
            errorMessage = "Server configuration not found"
            return
        }

        let status = await MCPClientService.shared.status(for: serverConfig.id)
        if !status.isConnected {
            await MainActor.run { isConnecting = true }
            do {
                try await MCPClientService.shared.ensureConnected(config: serverConfig)
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = "Failed to connect: \(error.localizedDescription)"
                }
                return
            }
            await MainActor.run { isConnecting = false }
        }

        // Step 2: Generate LLM content for fields that need it
        if let llmPrompt = actionConfig.llmPrompt {
            await generateLLMFields(prompt: llmPrompt)
        }

        // Step 3: Fetch picker options from MCP
        await fetchPickerOptions(serverConfig: serverConfig)

        // Focus first text field
        if let firstTextField = actionConfig.fields.first(where: { $0.type == .text }) {
            await MainActor.run { focusedField = firstTextField.id }
        }
    }

    private func generateLLMFields(prompt: MCPLLMPrompt) async {
        await MainActor.run {
            isGeneratingLLM = true
            fieldLoading[prompt.titleField] = true
            if let bodyField = prompt.bodyField {
                fieldLoading[bodyField] = true
            }
        }

        do {
            let messages = [
                ChatMessage(role: "system", content: prompt.systemPrompt),
                ChatMessage(role: "user", content: clipboardText)
            ]
            let response = try await LLMService.shared.generateWithMessages(messages)

            // Parse "TITLE: ...\n\n<body>" format
            let (title, body) = parseLLMResponse(response)

            await MainActor.run {
                fieldValues[prompt.titleField] = title
                if let bodyField = prompt.bodyField {
                    fieldValues[bodyField] = body
                }
                isGeneratingLLM = false
                fieldLoading[prompt.titleField] = false
                if let bodyField = prompt.bodyField {
                    fieldLoading[bodyField] = false
                }
            }
        } catch {
            await MainActor.run {
                isGeneratingLLM = false
                fieldLoading[prompt.titleField] = false
                if let bodyField = prompt.bodyField {
                    fieldLoading[bodyField] = false
                }
                // Don't block the form — user can type manually
                errorMessage = "AI generation failed — type manually"
            }
        }
    }

    private func parseLLMResponse(_ response: String) -> (title: String, body: String) {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try "TITLE: <title>\n\n<body>" format
        if trimmed.hasPrefix("TITLE:") {
            let afterTitle = trimmed.dropFirst("TITLE:".count).trimmingCharacters(in: .whitespaces)
            if let range = afterTitle.range(of: "\n\n") {
                let title = String(afterTitle[afterTitle.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let body = String(afterTitle[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return (title, body)
            }
            // No body separator — everything is title
            return (afterTitle, "")
        }

        // Fallback: first line = title, rest = body
        let lines = trimmed.components(separatedBy: "\n")
        let title = lines.first ?? trimmed
        let body = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
    }

    private func fetchPickerOptions(serverConfig: MCPServerConfig) async {
        // Fetch options for all picker/multiselect fields in parallel
        await withTaskGroup(of: (String, [MCPPickerOption]).self) { group in
            for field in actionConfig.fields {
                guard field.type == .picker || field.type == .multiselect else { continue }
                guard case .mcp(let toolName) = field.source else { continue }

                let fieldId = field.id

                await MainActor.run { fieldLoading[fieldId] = true }

                group.addTask {
                    do {
                        let options = try await MCPClientService.shared.fetchOptions(
                            serverConfigId: serverConfig.id,
                            toolName: toolName,
                            arguments: [:]
                        )
                        return (fieldId, options)
                    } catch {
                        return (fieldId, [])
                    }
                }
            }

            for await (fieldId, options) in group {
                await MainActor.run {
                    pickerOptions[fieldId] = options
                    fieldLoading[fieldId] = false
                }
            }
        }
    }

    // MARK: - Submit

    func submit() async {
        guard !isSubmitting else { return }

        // Validate required fields
        for field in actionConfig.fields where field.required {
            let value: String
            if field.type == .multiselect {
                let selected = multiSelectValues[field.id] ?? []
                value = selected.isEmpty ? "" : "has_value"
            } else {
                value = fieldValues[field.id] ?? ""
            }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await MainActor.run {
                    errorMessage = "\(field.label) is required"
                }
                return
            }
        }

        await MainActor.run {
            isSubmitting = true
            errorMessage = nil
        }

        // Build tool arguments from submitMapping, converting to MCP Value types
        var arguments: [String: Value] = [:]
        for (toolParam, template) in actionConfig.submitMapping {
            let resolved = resolveTemplate(template)
            // Arrays (comma-separated) → JSON array value
            if resolved.contains(",") && isArrayField(template) {
                let items = resolved.components(separatedBy: ",").map { Value.string($0.trimmingCharacters(in: .whitespaces)) }
                arguments[toolParam] = .array(items)
            } else {
                arguments[toolParam] = .string(resolved)
            }
        }

        do {
            let result = try await MCPClientService.shared.callTool(
                serverConfigId: actionConfig.serverConfigId,
                toolName: actionConfig.submitTool,
                arguments: arguments
            )

            await MainActor.run {
                isSubmitting = false
                successMessage = "Created successfully"
                CrashReportingService.shared.addBreadcrumb(
                    category: "mcp",
                    message: "Tool call succeeded: \(actionConfig.submitTool)"
                )
            }

            // Copy result URL or text to clipboard if available
            if !result.isEmpty {
                SystemActions.copyToClipboard(result)
            }
        } catch {
            await MainActor.run {
                isSubmitting = false
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Resolves a template like "{{title}}" or "{{labels}}" from field values.
    private func resolveTemplate(_ template: String) -> String {
        // Match {{fieldId}} or {{fieldId.property}}
        var result = template
        let pattern = "\\{\\{([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }
        let matches = regex.matches(in: template, range: NSRange(template.startIndex..., in: template))

        for match in matches.reversed() {
            guard let range = Range(match.range(at: 1), in: template) else { continue }
            let key = String(template[range])
            let replacement: String

            // Check multiselect first
            if let selected = multiSelectValues[key], !selected.isEmpty {
                replacement = selected.sorted().joined(separator: ",")
            } else {
                replacement = fieldValues[key] ?? ""
            }

            if let fullRange = Range(match.range, in: result) {
                result.replaceSubrange(fullRange, with: replacement)
            }
        }

        return result
    }

    /// Checks if a template references a multiselect field (which produces comma-separated values).
    private func isArrayField(_ template: String) -> Bool {
        let pattern = "\\{\\{([^}]+)\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: template, range: NSRange(template.startIndex..., in: template)),
              let range = Range(match.range(at: 1), in: template) else { return false }
        let key = String(template[range])
        return multiSelectValues[key] != nil
    }
}

// MARK: - Flow Layout

/// Simple horizontal flow layout for chips/tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
