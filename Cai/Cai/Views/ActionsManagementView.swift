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
///
/// **Note (2026-05-07):** previously composed `ManagementScreen` (the
/// generic shell shared with Destinations), but that broke SwiftUI
/// `List`'s drag-to-reorder gesture in the embedded
/// `ShortcutsManagementView` for reasons not fully understood — likely
/// related to how the generic ViewBuilder closure interacts with
/// NSTableView's drag responder chain. Reverted to direct VStack
/// composition (matching the known-working structure from commit
/// 4be222d) until we figure out a way to share the shell without
/// breaking drag.
struct ActionsManagementView: View {
    @ObservedObject var settings = CaiSettings.shared
    let onBack: () -> Void
    var onBrowseExtensions: (() -> Void)?

    enum Tab: Hashable {
        case custom, builtIn
    }

    @State private var selectedTab: Tab = .custom

    /// Reference to the embedded `ShortcutsManagementView`'s identity. The
    /// parent header's `+` button bumps this UUID to remount the inner
    /// view in a fresh-add state.
    @State private var customAddRequest: UUID = UUID()

    var body: some View {
        // INCREMENTAL DRAG-FIX TEST: re-adding parent VStack + TabBar
        // wrapper to see if it breaks drag. If drag still works, the
        // wrapper isn't the killer.
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

            switch selectedTab {
            case .custom:
                ShortcutsManagementView(
                    onBack: onBack,
                    onBrowseExtensions: onBrowseExtensions,
                    showsChrome: false,
                    externalAddTrigger: customAddRequest
                )
                // NOTE (2026-05-07): no `.id(customAddRequest)` here on
                // purpose. With `.id`, the embedded view remounts on every
                // `+` tap — fresh instance, no previous `externalAddTrigger`
                // value, so `.onChange` never fires and the add form
                // doesn't open. Without `.id`, the view stays mounted and
                // `.onChange(of: externalAddTrigger)` in the body fires
                // each time the parent bumps the UUID, calling
                // `cancelForm() + beginAdding()`. Same effect, working
                // wiring.
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

            // `+` only on the Custom tab. Bumps `customAddRequest` to
            // remount the embedded view in fresh-add state.
            if selectedTab == .custom {
                Button(action: {
                    customAddRequest = UUID()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.caiPrimary)
                }
                .buttonStyle(.plain)
                .help("Add a new custom action")
            }
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
