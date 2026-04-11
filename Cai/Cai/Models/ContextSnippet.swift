import Foundation

// MARK: - Context Snippet

/// A per-app system prompt enrichment. When the user triggers an LLM action
/// and the frontmost app's bundleId matches, this snippet is injected into
/// the LLM system prompt as a structured `[App context: {appName}]` section.
///
/// Example — a user with a Terminal snippet configured:
///   "When I copy from Terminal, I'm usually debugging a Rails app."
/// …sees every LLM action from Terminal enriched with that context.
///
/// **Design notes:**
/// - `bundleId` is the canonical match key (stable across machines, languages, app rebrands)
/// - `appName` is display-hint metadata only (for UI / help docs / "App context" header)
/// - `id` is auto-generated when missing from JSON. In v1 it's ephemeral (regenerated
///   on each app launch since the file is read-only). When v1.1 Settings UI starts
///   persisting edits, the first save writes the in-memory id back to disk and it
///   becomes stable. Kept for v1.1 SwiftUI `ForEach` diffing and edit-state tracking.
/// - `enabled` defaults to `true` when missing from JSON. Lets users author minimal
///   3-field snippets (`bundleId`, `appName`, `context`) without ceremony.
/// - `Equatable` is auto-synthesized and unlocks v1.1 `ForEach` identity tracking
struct ContextSnippet: Codable, Identifiable, Equatable {
    var id: UUID
    var bundleId: String
    var appName: String
    var context: String
    var enabled: Bool

    init(id: UUID = UUID(), bundleId: String, appName: String, context: String, enabled: Bool = true) {
        self.id = id
        self.bundleId = bundleId
        self.appName = appName
        self.context = context
        self.enabled = enabled
    }

    /// Custom decoder makes `id` and `enabled` optional in the JSON file format
    /// so users can hand-author `~/.config/cai/snippets.json` without typing UUIDs
    /// or remembering to set `enabled: true`. The Swift initializer's defaults
    /// only apply to call-site construction — Swift's auto-synthesized `init(from:)`
    /// ignores them and requires every field to be present in the JSON. This custom
    /// decoder bridges that gap.
    ///
    /// **Required fields:** `bundleId`, `appName`, `context` (no sensible defaults).
    /// **Optional fields:** `id` (auto-generated if missing), `enabled` (defaults to `true`).
    ///
    /// **Encode side:** We deliberately do NOT override `encode(to:)`. Swift continues
    /// to auto-synthesize a complete encoder that writes all five fields to JSON,
    /// so any future write path (v1.1 Settings UI) round-trips the model verbatim.
    private enum CodingKeys: String, CodingKey {
        case id, bundleId, appName, context, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.bundleId = try c.decode(String.self, forKey: .bundleId)
        self.appName = try c.decode(String.self, forKey: .appName)
        self.context = try c.decode(String.self, forKey: .context)
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    /// Advisory maximum length for the context string. Not enforced at the model level —
    /// v1.1 Settings UI will show a char counter, and the 50K-char LLM input cap in
    /// `LLMService.truncateMessages` provides a hard safety net.
    static let maxContextLength = 500
}

// MARK: - JSON File Envelope

/// On-disk JSON envelope for `~/.config/cai/snippets.json`. Includes a `version`
/// field so future schema changes can be migrated cleanly.
///
/// Designed to be portable: a future Settings Export/Import feature will embed
/// this struct verbatim inside a larger `cai-settings.json` blob. No timestamps,
/// no machine-specific paths, no local-only fields.
struct ContextSnippetsFile: Codable {
    /// Schema version. Always `1` in this PR. Future versions will migrate
    /// on load (or reject with a clear error if downgrading).
    var version: Int

    /// All configured snippets. Empty array is a valid state.
    var snippets: [ContextSnippet]
}
