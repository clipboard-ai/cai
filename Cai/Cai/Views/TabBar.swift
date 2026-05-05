import SwiftUI

/// Reusable two-tab segmented bar with optional per-tab counts.
///
/// Used by parent management screens that group related sub-screens
/// (`ActionsManagementView` for Custom + Built-in actions;
/// `DestinationsParentView` for Built-in + Custom destinations) so the
/// user can switch context without leaving the screen.
///
/// **Visual language:** echoes the chip vocabulary established in
/// DESIGN.md — neutral surface for inactive tab, indigo wash + indigo
/// label for active tab. Borderless segments with a hairline divider
/// between them. Compact (28pt height) so it fits cleanly under the
/// screen header without competing for vertical space.
///
/// Generic over a tab identifier — typically a tiny enum like
/// `enum ActionsTab { case custom, builtIn }` declared by the caller.
struct TabBar<Tab: Hashable>: View {
    @Binding var selection: Tab
    let tabs: [TabSpec<Tab>]

    struct TabSpec<T: Hashable>: Identifiable {
        let id: T
        let label: String
        let count: Int?
        init(id: T, label: String, count: Int? = nil) {
            self.id = id
            self.label = label
            self.count = count
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                tabButton(tab)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.caiSurface.opacity(0.5))
        )
    }

    private func tabButton(_ tab: TabSpec<Tab>) -> some View {
        let isActive = selection == tab.id
        return Button(action: {
            withAnimation(.easeOut(duration: 0.15)) {
                selection = tab.id
            }
        }) {
            HStack(spacing: 5) {
                Text(tab.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isActive ? .caiPrimary : .caiTextSecondary)
                if let count = tab.count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(
                            isActive
                                ? .caiPrimary.opacity(0.7)
                                : .caiTextSecondary.opacity(0.6)
                        )
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? Color.caiPrimary.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
