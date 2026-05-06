import SwiftUI

/// Unified "Actions" screen — combines Custom actions (user-created) and
/// Built-in actions (Cai's pre-bundled set, hide/show toggle) under a
/// single tabbed parent. Replaces the separate `Custom Actions` and
/// `Built-in Actions` Settings entries.
///
/// **Design (locked 2026-05-05):**
/// - Custom tab is default (most-used).
/// - Tab bar shows per-tab count: `Custom (12) | Built-in (8)`.
/// - The `+` add button only renders in the header on the Custom tab —
///   Built-in actions can't be added by the user.
/// - The two tabs use different row patterns intentionally:
///   - Custom: full-CRUD row + inline edit form (`ShortcutsManagementView`)
///   - Built-in: hide/show toggle row (`BuiltInActionsContent`)
/// - Container chrome (header + footer) is unified via `ManagementScreen`
///   so this screen and `DestinationsManagementView` are pixel-identical
///   at the shell level by construction.
struct ActionsManagementView: View {
    @ObservedObject var settings = CaiSettings.shared
    let onBack: () -> Void
    var onBrowseExtensions: (() -> Void)?

    enum Tab: Hashable {
        case custom, builtIn
    }

    @State private var selectedTab: Tab = .custom

    /// Bumped on `+` tap. The embedded `ShortcutsManagementView` watches
    /// this via its `externalAddTrigger` parameter and opens a fresh add
    /// form when it changes. Lets the parent header's `+` drive the same
    /// flow as the embedded view's own internal `+`, without the view
    /// re-mount that an `.id()` trick would cause.
    @State private var customAddRequest: UUID = UUID()

    var body: some View {
        ManagementScreen(
            icon: "bolt.circle.fill",
            title: "Actions",
            subtitle: headerSubtitle,
            tabs: [
                .init(id: .custom, label: "Custom", count: settings.shortcuts.count),
                .init(id: .builtIn, label: "Built-in", count: visibleBuiltInCount)
            ],
            selection: $selectedTab,
            customTabId: .custom,
            onAdd: { customAddRequest = UUID() }
        ) {
            switch selectedTab {
            case .custom:
                ShortcutsManagementView(
                    onBack: onBack,
                    onBrowseExtensions: onBrowseExtensions,
                    showsChrome: false,
                    externalAddTrigger: customAddRequest
                )
            case .builtIn:
                BuiltInActionsContent()
            }
        }
    }

    private var headerSubtitle: String {
        switch selectedTab {
        case .custom:
            return settings.shortcuts.isEmpty
                ? "Type to filter actions when Cai is open"
                : "\(settings.shortcuts.count) custom action\(settings.shortcuts.count == 1 ? "" : "s")"
        case .builtIn:
            return "\(visibleBuiltInCount) of \(BuiltInActionID.allCases.count) visible"
        }
    }

    private var visibleBuiltInCount: Int {
        BuiltInActionID.allCases.filter {
            !settings.hiddenBuiltInActions.contains($0.rawValue)
        }.count
    }
}
