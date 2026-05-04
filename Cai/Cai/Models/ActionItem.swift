import Foundation

// MARK: - Action Models

struct ActionItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let icon: String  // SF Symbol name
    let shortcut: Int
    let type: ActionType
    /// Set by shortcut-driven actions where the user has opted in to
    /// auto-pasting the LLM response back over their selection.
    var autoReplaceSelection: Bool = false
    /// Names of actions to run after this one completes (chain). Snapshot of
    /// the source `CaiShortcut.next` / `OutputDestination.next` taken at
    /// generation time. Empty means no chain. When non-empty, dispatch forces
    /// the background path so `ChainExecutor` can run silently with menu-bar
    /// pulse + terminal toast UX.
    var next: [String] = []
    /// Used by `.prompt`-type shortcuts to opt into silent background dispatch
    /// (dismiss Cai immediately, run the LLM call off-screen, surface result as
    /// a toast). Shell shortcuts carry the same flag inline on the
    /// `.shortcutShell` enum case; this field is for the prompt path.
    var runInBackground: Bool = false
}

enum ActionType {
    case openURL(URL)
    case openMaps(String)
    case createCalendar(title: String, date: Date, location: String?, description: String? = nil)
    case search(String)
    case llmAction(LLMAction)
    case jsonPrettyPrint(String)
    case customPrompt
    case shortcutURL(String)  // URL template with %s placeholder
    case shortcutShell(command: String, runInBackground: Bool)  // Shell command template; runInBackground dismisses Cai + toasts on completion
    case outputDestination(OutputDestination)  // Send text to external app/service
    case copyText  // Show extracted text in ResultView (used by "Show Extracted Text" from image OCR)
    case installExtension  // Install community extension from clipboard YAML
    case mcpAction(configId: String)  // MCP-powered action (e.g., "Create GitHub Issue")
}

enum LLMAction {
    case summarize
    case translate(String)
    case define
    case explain
    case reply
    case proofread
    case custom(String)
}
