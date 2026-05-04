import Foundation

// MARK: - Output Destination Model

/// An output destination defines where to send text after processing.
/// Built-in destinations (Mail, Notes, Reminders) work zero-config.
/// Custom destinations use webhooks, URL schemes, or shell commands.
struct OutputDestination: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var icon: String                    // SF Symbol name
    var type: DestinationType
    var isEnabled: Bool
    var isBuiltIn: Bool                 // true for Mail, Notes, Reminders
    var showInActionList: Bool          // also show as direct-route action (no LLM step)
    var setupFields: [SetupField]       // user-configurable values (API keys, etc.)
    /// Names of additional actions (shortcuts or destinations) to run after
    /// this one completes. Sequential pipe — each step's output becomes the
    /// next step's `{{result}}`. NOT routed through the system clipboard:
    /// the chain executor uses an in-memory pipe so the user can copy other
    /// text mid-chain without breaking the flow.
    /// Empty array means "no chaining" (the default). Lookup is by `name`,
    /// preferring shortcuts over destinations on collision.
    /// Cycle detection + max-depth-10 guard the executor against runaway loops.
    var next: [String]

    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        type: DestinationType,
        isEnabled: Bool = true,
        isBuiltIn: Bool = false,
        showInActionList: Bool = false,
        setupFields: [SetupField] = [],
        next: [String] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.type = type
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.showInActionList = showInActionList
        self.setupFields = setupFields
        self.next = next
    }

    /// Custom decoder — `decodeIfPresent` for `next` so previously-persisted
    /// destinations (without the field) decode cleanly with an empty list.
    /// Encode stays synthesized; all fields are always written.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.icon = try c.decode(String.self, forKey: .icon)
        self.type = try c.decode(DestinationType.self, forKey: .type)
        self.isEnabled = try c.decode(Bool.self, forKey: .isEnabled)
        self.isBuiltIn = try c.decode(Bool.self, forKey: .isBuiltIn)
        self.showInActionList = try c.decode(Bool.self, forKey: .showInActionList)
        self.setupFields = try c.decode([SetupField].self, forKey: .setupFields)
        self.next = try c.decodeIfPresent([String].self, forKey: .next) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, type, isEnabled, isBuiltIn, showInActionList, setupFields, next
    }

    /// Whether all required setup fields have values
    var isConfigured: Bool {
        setupFields.allSatisfy { !$0.value.isEmpty }
    }
}

// MARK: - Destination Type

enum DestinationType: Equatable {
    case applescript(template: String)
    case webhook(WebhookConfig)
    case deeplink(template: String)
    case shell(command: String)
    /// Pastes the result over the current selection in the source app
    /// (the app that was frontmost when Cai was invoked). No template:
    /// the LLM result text is pasted verbatim via simulated Cmd+V.
    case pasteBack

    var label: String {
        switch self {
        case .applescript: return "AppleScript"
        case .webhook: return "Webhook"
        case .deeplink: return "Deeplink"
        case .shell: return "Shell Command"
        case .pasteBack: return "Replace Selection"
        }
    }

    /// String tag for picker identification
    var tag: String {
        switch self {
        case .applescript: return "applescript"
        case .webhook: return "webhook"
        case .deeplink: return "deeplink"
        case .shell: return "shell"
        case .pasteBack: return "pasteBack"
        }
    }
}

// MARK: - DestinationType Codable (with urlScheme migration)

extension DestinationType: Codable {
    private enum CodingKeys: String, CodingKey {
        case applescript, webhook, deeplink, shell, pasteBack
        case urlScheme // legacy
    }

    private enum NestedKeys: String, CodingKey {
        case template, command
        case _0 // unlabeled associated value (webhook)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.applescript) {
            let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .applescript)
            self = .applescript(template: try nested.decode(String.self, forKey: .template))
        } else if container.contains(.webhook) {
            let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .webhook)
            self = .webhook(try nested.decode(WebhookConfig.self, forKey: ._0))
        } else if container.contains(.deeplink) {
            let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .deeplink)
            self = .deeplink(template: try nested.decode(String.self, forKey: .template))
        } else if container.contains(.urlScheme) {
            // Migrate old "urlScheme" → .deeplink
            let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .urlScheme)
            self = .deeplink(template: try nested.decode(String.self, forKey: .template))
        } else if container.contains(.shell) {
            let nested = try container.nestedContainer(keyedBy: NestedKeys.self, forKey: .shell)
            self = .shell(command: try nested.decode(String.self, forKey: .command))
        } else if container.contains(.pasteBack) {
            self = .pasteBack
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown destination type"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .applescript(let template):
            var nested = container.nestedContainer(keyedBy: NestedKeys.self, forKey: .applescript)
            try nested.encode(template, forKey: .template)
        case .webhook(let config):
            var nested = container.nestedContainer(keyedBy: NestedKeys.self, forKey: .webhook)
            try nested.encode(config, forKey: ._0)
        case .deeplink(let template):
            var nested = container.nestedContainer(keyedBy: NestedKeys.self, forKey: .deeplink)
            try nested.encode(template, forKey: .template)
        case .shell(let command):
            var nested = container.nestedContainer(keyedBy: NestedKeys.self, forKey: .shell)
            try nested.encode(command, forKey: .command)
        case .pasteBack:
            // No associated value: presence of the key is the signal.
            try container.encode(true, forKey: .pasteBack)
        }
    }
}

// MARK: - Webhook Config

struct WebhookConfig: Codable, Equatable {
    var url: String
    var method: String                  // "POST", "PUT", etc.
    var headers: [String: String]
    var bodyTemplate: String            // JSON string with {{result}} placeholder

    init(
        url: String,
        method: String = "POST",
        headers: [String: String] = ["Content-Type": "application/json"],
        bodyTemplate: String
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.bodyTemplate = bodyTemplate
    }
}

// MARK: - Setup Field

/// A user-configurable field like an API key or webhook URL.
/// Stored locally; resolved at execution time via {{key}} placeholders.
struct SetupField: Codable, Identifiable, Equatable {
    let id: UUID
    var key: String                     // placeholder key, e.g. "api_key"
    var value: String                   // user-provided value
    var isSecret: Bool                  // mask in UI

    init(
        id: UUID = UUID(),
        key: String,
        value: String = "",
        isSecret: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.isSecret = isSecret
    }
}

// MARK: - Errors

enum OutputDestinationError: LocalizedError {
    case appleScriptFailed(String)
    case webhookFailed(Int, String)
    case invalidURL
    case shellFailed(Int, String)
    case notConfigured(String)
    case timeout
    case pasteBackFailed

    var errorDescription: String? {
        switch self {
        case .appleScriptFailed(let msg):
            return "AppleScript error: \(msg)"
        case .webhookFailed(let code, let msg):
            return "Webhook failed (\(code)): \(msg)"
        case .invalidURL:
            return "Invalid URL"
        case .shellFailed(let code, let msg):
            return "Command failed (\(code)): \(msg)"
        case .notConfigured(let field):
            return "Missing setup: \(field)"
        case .timeout:
            // Avoid the substring "timed out" so ResultView's provider-error
            // heuristic doesn't show the misleading "Check Settings → Model
            // Provider" hint for a shell-side timeout.
            return "Shell command exceeded 60s and was stopped"
        case .pasteBackFailed:
            return "Could not paste the response. Check Accessibility permission."
        }
    }
}
