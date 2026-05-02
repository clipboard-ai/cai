import Foundation

/// Single source of truth for built-in action identifiers that can be hidden
/// via Settings → Built-in Actions.
///
/// `rawValue` matches the `ActionItem.id` produced by `ActionGenerator`.
/// `CaiSettings.hiddenBuiltInActions` stores the raw values of hidden actions.
///
/// Two actions are deliberately omitted because they are load-bearing entry
/// points for their content type:
/// - `install_extension` — hiding leaves users unable to install extensions.
/// - `extract_text` — hiding removes the OCR-result entry point for image
///   clipboards (text-on-extracted-text actions still work, but the user can't
///   review the raw OCR text).
enum BuiltInActionID: String, CaseIterable {
    // Universal LLM actions (apply to many content types)
    case askAI = "custom_prompt"
    case summarize
    case explain
    case reply
    case proofread
    case translate
    case searchWeb = "search_web"
    case defineWord = "define_word"

    // Type-specific actions (apply only to one content type)
    case openURL = "open_url"
    case openMaps = "open_maps"
    case createEvent = "create_event"
    case prettyPrint = "pretty_print"

    /// Human-readable label for the toggle row in `BuiltInActionsView`.
    var displayLabel: String {
        switch self {
        case .askAI: return "Ask AI"
        case .summarize: return "Summarize"
        case .explain: return "Explain"
        case .reply: return "Reply"
        case .proofread: return "Fix Grammar"
        case .translate: return "Translate"
        case .searchWeb: return "Search Web"
        case .defineWord: return "Define Word"
        case .openURL: return "Open in Browser"
        case .openMaps: return "Open in Maps"
        case .createEvent: return "Create Calendar Event"
        case .prettyPrint: return "Pretty Print JSON"
        }
    }

    /// SF Symbol used in the action list — reused in the toggle row so the
    /// user sees the same affordance they're enabling/disabling.
    var iconName: String {
        switch self {
        case .askAI: return "bolt.fill"
        case .summarize: return "text.redaction"
        case .explain: return "lightbulb"
        case .reply: return "arrowshape.turn.up.left"
        case .proofread: return "pencil.and.outline"
        case .translate: return "globe"
        case .searchWeb: return "magnifyingglass"
        case .defineWord: return "character.book.closed"
        case .openURL: return "safari"
        case .openMaps: return "map"
        case .createEvent: return "calendar.badge.plus"
        case .prettyPrint: return "curlybraces"
        }
    }

    /// Short description shown under the label. Communicates scope so the user
    /// can predict what hiding will affect ("URL clipboards", "prose only", etc.).
    var scopeDescription: String {
        switch self {
        case .askAI: return "Universal · Custom prompt for any clipboard content"
        case .summarize: return "Universal · Text 100+ chars"
        case .explain: return "Universal"
        case .reply: return "Universal · Sentences and images"
        case .proofread: return "Universal · Sentences and images"
        case .translate: return "Universal"
        case .searchWeb: return "Universal · Text under 500 chars"
        case .defineWord: return "Type-specific · Single word"
        case .openURL: return "Type-specific · URLs "
        case .openMaps: return "Type-specific · Address or meeting location"
        case .createEvent: return "Type-specific · Detected meeting"
        case .prettyPrint: return "Type-specific · JSON"
        }
    }

    /// Grouping for documentation purposes (used in scope text). Not currently
    /// used to render separate sections — the Connectors-style single-section
    /// layout makes scope visible per-row via `scopeDescription`.
    enum Category {
        case universal, typeSpecific
    }

    var category: Category {
        switch self {
        case .askAI, .summarize, .explain, .reply, .proofread, .translate, .searchWeb, .defineWord:
            return .universal
        case .openURL, .openMaps, .createEvent, .prettyPrint:
            return .typeSpecific
        }
    }
}
