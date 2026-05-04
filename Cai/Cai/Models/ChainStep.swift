import Foundation

/// One step in a chain (`CaiShortcut.next` / `OutputDestination.next`).
///
/// Replaces the v1.6 `[String]` representation. The string-only form was
/// adequate for "list of named Cai actions" but couldn't carry the metadata
/// inline-LLM steps (a per-step directive) and Apple Shortcuts integration
/// (provenance tag — Cai vs. Shortcuts.app) needed.
///
/// **Cases:**
/// - `.action(name:)` — references an existing `CaiShortcut` or
///   `OutputDestination` by name. Lookup happens at execute time in
///   `ChainExecutor.resolve(_:)`. Shortcuts win on collision with destinations.
/// - `.inlineLLM(directive:)` — runs the chain pipe value through the local
///   LLM with `directive` as the system prompt. Reuses `LLMService.buildMessages`
///   so "About You" + per-app Context Snippets are injected consistently with
///   prompt-type shortcuts.
/// - `.appleShortcut(name:)` — invokes a user-authored Apple Shortcuts.app
///   shortcut by name via the `/usr/bin/shortcuts run` CLI. The chain pipe
///   value is passed via stdin (Shortcuts that accept text input consume it;
///   ones that don't silently ignore it). Stdout flows back into the pipe.
///
/// **Codable:** uses a tagged-union representation (`{"type": "...", ...}`).
/// Auto-synthesized — no custom encoder/decoder needed. Storage migration
/// from v1.6's `[String]`: not implemented because the v1.6 chain-feature
/// code never shipped (still on `feat/template-engine` branch). Once we
/// merge to master, in-progress branch users would need `git stash` of any
/// chain config.
///
/// **Future:** `.mcpAction(presetId:)` is reserved for v1.8 once we design
/// "preset MCP actions" (saved partial-fill of an MCP form, e.g. "create
/// GitHub issue in cai/cai with the bug label").
enum ChainStep: Codable, Equatable, Hashable {
    case action(name: String)
    case inlineLLM(directive: String)
    case appleShortcut(name: String)

    /// Short label for chip rendering. Truncated by the UI.
    /// - `.action` → the action name
    /// - `.inlineLLM` → the directive (italic in chip render)
    /// - `.appleShortcut` → the shortcut name
    var displayLabel: String {
        switch self {
        case .action(let name): return name
        case .inlineLLM(let directive): return directive
        case .appleShortcut(let name): return name
        }
    }

    /// True when the step has no meaningful content. Used by the editor to
    /// auto-remove inline-LLM chips whose directive is left empty after edit
    /// (matches NSTokenField / Linear pill convention: empty token = no token).
    var isEmpty: Bool {
        switch self {
        case .action(let name): return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .inlineLLM(let directive): return directive.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .appleShortcut(let name): return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
