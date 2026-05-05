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
/// - Container chrome (header + footer) is unified at the parent so the
///   tabs feel like one screen, not two stacked windows.
struct ActionsManagementView: View {
    @ObservedObject var settings = CaiSettings.shared
    let onBack: () -> Void
    var onBrowseExtensions: (() -> Void)?

    enum Tab: Hashable {
        case custom, builtIn
    }

    @State private var selectedTab: Tab = .custom

    /// Reference to the embedded `ShortcutsManagementView` so the parent
    /// header's `+` button can call into its add flow without duplicating
    /// the cancel-form-then-begin-adding logic.
    @State private var customAddRequest: UUID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.caiDivider)

            TabBar(
                selection: $selectedTab,
                tabs: [
                    .init(id: .custom, label: "Custom", count: settings.shortcuts.count),
                    .init(id: .builtIn, label: "Built-in", count: visibleBuiltInCount)
                ]
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Tab content. Embedded views render WITHOUT their own chrome
            // (header/footer) so the parent's header + footer are the only
            // ones visible — feels like one screen.
            switch selectedTab {
            case .custom:
                ShortcutsManagementView(
                    onBack: onBack,
                    onBrowseExtensions: onBrowseExtensions,
                    showsChrome: false
                )
                .id(customAddRequest)  // forcing identity refresh allows external "+"
            case .builtIn:
                BuiltInActionsContent()
            }

            Spacer(minLength: 0)
            Divider().background(Color.caiDivider)
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.circle.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.caiPrimary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Actions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.caiTextPrimary)

                Text(headerSubtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.caiTextSecondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
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

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            KeyboardHint(key: "Esc", label: "Back")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
